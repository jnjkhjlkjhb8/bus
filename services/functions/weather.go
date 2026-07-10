package main

import (
	"encoding/json"
	"os"
	"strconv"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
)

// cwaBase is the base URL of the CWA (Central Weather Administration) open-data
// datastore API. Docs: https://opendata.cwa.gov.tw/
const cwaBase = "https://opendata.cwa.gov.tw/api/v1/rest/datastore"

// weatherData is the per-city weather snapshot cached in Redis and used as ETA
// prediction features.
type weatherData struct {
	Temperature   float64 `json:"temperature"`
	Precipitation float64 `json:"precipitation"`
	WindSpeed     float64 `json:"wind_speed"`
	Humidity      float64 `json:"humidity"`
}

// countyToCity maps the CWA station's Chinese county name to the internal city
// code, so observation records can be bucketed per city. Stations in counties
// not listed here are ignored.
var countyToCity = map[string]string{
	"臺北市": "Taipei", "新北市": "NewTaipei", "桃園市": "Taoyuan",
	"臺中市": "Taichung", "臺南市": "Tainan", "高雄市": "Kaohsiung",
	"基隆市": "Keelung", "新竹市": "Hsinchu", "新竹縣": "HsinchuCounty",
	"苗栗縣": "MiaoliCounty", "彰化縣": "ChanghuaCounty", "南投縣": "NantouCounty",
	"雲林縣": "YunlinCounty", "嘉義市": "Chiayi", "嘉義縣": "ChiayiCounty",
	"屏東縣": "PingtungCounty", "宜蘭縣": "YilanCounty", "花蓮縣": "HualienCounty",
	"臺東縣": "TaitungCounty", "澎湖縣": "PenghuCounty", "金門縣": "KinmenCounty",
	"連江縣": "LienchiangCounty",
}

// weatherSync fetches current weather from two CWA datasets and caches a merged
// per-city snapshot in Redis (weather:<city>, 60-minute TTL) for ETA prediction.
// O-A0003-001 supplies station observations (temperature, wind, humidity) and
// O-A0002-001 supplies rainfall stations (precipitation), each taking the most
// recent station per city. No-op when CWA_API_KEY is unset; a failure of either
// dataset is logged and the other's data is still cached. The TTL runs well ahead
// of the 10-minute refresh cron so a single transient CWA failure leaves a
// slightly stale snapshot in place rather than nulling the weather features on
// every bus_eta_history row written until the next success.
func weatherSync(rc *redis.Client) {
	cwaKey := os.Getenv("CWA_API_KEY")
	if cwaKey == "" {
		log.Infof("[WEATHER] CWA_API_KEY not set, skipping")
		return
	}
	client := resty.New()
	merged := make(map[string]weatherData)

	var obs struct {
		Records struct {
			Station []struct {
				GeoInfo struct {
					CountyName string `json:"CountyName"`
				} `json:"GeoInfo"`
				ObsTime struct {
					DateTime string `json:"DateTime"`
				} `json:"ObsTime"`
				WeatherElement struct {
					AirTemperature   string `json:"AirTemperature"`
					WindSpeed        string `json:"WindSpeed"`
					RelativeHumidity string `json:"RelativeHumidity"`
				} `json:"WeatherElement"`
			} `json:"Station"`
		} `json:"records"`
	}
	type stationBest struct {
		obsTime time.Time
		data    weatherData
	}
	best := make(map[string]stationBest)

	resp, err := client.R().SetHeader("Authorization", cwaKey).
		Get(cwaBase + "/O-A0003-001")
	if err == nil && resp.StatusCode() == 200 {
		if jsonErr := json.Unmarshal(resp.Body(), &obs); jsonErr == nil {
			for _, s := range obs.Records.Station {
				city, ok := countyToCity[s.GeoInfo.CountyName]
				if !ok {
					continue
				}
				t, _ := time.Parse(time.RFC3339, s.ObsTime.DateTime)
				if prev, exists := best[city]; exists && !t.After(prev.obsTime) {
					continue
				}
				d := weatherData{}
				if v, err := strconv.ParseFloat(s.WeatherElement.AirTemperature, 64); err == nil && v > -90 {
					d.Temperature = v
				}
				if v, err := strconv.ParseFloat(s.WeatherElement.WindSpeed, 64); err == nil && v > -90 {
					d.WindSpeed = v
				}
				if v, err := strconv.ParseFloat(s.WeatherElement.RelativeHumidity, 64); err == nil && v > -90 {
					d.Humidity = v
				}
				best[city] = stationBest{t, d}
			}
		}
		for city, b := range best {
			merged[city] = b.data
		}
	} else if err != nil {
		log.Infof("[WEATHER] O-A0003-001 fetch error: %v", err)
	} else {
		log.Infof("[WEATHER] O-A0003-001 error status=%d", resp.StatusCode())
	}

	// Precipitation comes from the automatic rainfall-station dataset (O-A0002-001),
	// bucketed per city exactly like the observation stations above: the newest
	// station per county wins, contributing its "Now" 10-minute accumulation. This
	// replaced the former F-B0046-001 precipitation grid, whose dataset id CWA
	// retired — it now 404s, so the whole grid branch was skipped and precipitation
	// was never written.
	var rain struct {
		Records struct {
			Station []struct {
				GeoInfo struct {
					CountyName string `json:"CountyName"`
				} `json:"GeoInfo"`
				ObsTime struct {
					DateTime string `json:"DateTime"`
				} `json:"ObsTime"`
				RainfallElement struct {
					Now struct {
						Precipitation string `json:"Precipitation"`
					} `json:"Now"`
				} `json:"RainfallElement"`
			} `json:"Station"`
		} `json:"records"`
	}
	type rainBest struct {
		obsTime time.Time
		precip  float64
	}
	bestRain := make(map[string]rainBest)
	resp2, err2 := client.R().SetHeader("Authorization", cwaKey).
		Get(cwaBase + "/O-A0002-001")
	if err2 == nil && resp2.StatusCode() == 200 {
		if jsonErr := json.Unmarshal(resp2.Body(), &rain); jsonErr == nil {
			for _, s := range rain.Records.Station {
				city, ok := countyToCity[s.GeoInfo.CountyName]
				if !ok {
					continue
				}
				t, _ := time.Parse(time.RFC3339, s.ObsTime.DateTime)
				if prev, exists := bestRain[city]; exists && !t.After(prev.obsTime) {
					continue
				}
				// CWA flags no-data with negative sentinels (e.g. -99); skip those so
				// precipitation stays unset rather than recording a bogus value.
				v, err := strconv.ParseFloat(s.RainfallElement.Now.Precipitation, 64)
				if err != nil || v < 0 {
					continue
				}
				bestRain[city] = rainBest{t, v}
			}
			for city, b := range bestRain {
				d := merged[city]
				d.Precipitation = b.precip
				merged[city] = d
			}
		}
	} else if err2 != nil {
		log.Infof("[WEATHER] O-A0002-001 fetch error: %v", err2)
	} else {
		log.Infof("[WEATHER] O-A0002-001 error status=%d", resp2.StatusCode())
	}

	for city, d := range merged {
		b, _ := json.Marshal(d)
		rc.Set(shared.WeatherKey(city), string(b), 60*time.Minute)
	}
	log.Infof("[WEATHER] synced %d cities", len(merged))
}
