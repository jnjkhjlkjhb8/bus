package main

import (
	"encoding/json"
	"math"
	"os"
	"strconv"
	"strings"
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

// cityCoords maps a city to a representative {lat, lon} used to sample the
// precipitation grid at that city's location.
var cityCoords = map[string][2]float64{
	"Taipei":         {25.04, 121.55},
	"NewTaipei":      {24.99, 121.46},
	"Taoyuan":        {24.99, 121.22},
	"Taichung":       {24.14, 120.67},
	"Tainan":         {22.99, 120.22},
	"Kaohsiung":      {22.65, 120.31},
	"Keelung":        {25.13, 121.73},
	"Hsinchu":        {24.80, 120.97},
	"HsinchuCounty":  {24.67, 121.00},
	"MiaoliCounty":   {24.56, 120.82},
	"ChanghuaCounty": {24.07, 120.52},
	"NantouCounty":   {23.96, 120.68},
	"YunlinCounty":   {23.71, 120.40},
	"Chiayi":         {23.48, 120.45},
	"ChiayiCounty":   {23.45, 120.45},
	"PingtungCounty": {22.54, 120.49},
	"YilanCounty":    {24.70, 121.75},
	"HualienCounty":  {23.99, 121.60},
	"TaitungCounty":  {22.75, 121.11},
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
	"臺東縣": "TaitungCounty",
}

// gridPrecipitation samples the CWA precipitation grid at (lon, lat) by rounding
// to the nearest grid cell. It returns nil when the point falls outside the grid
// or the cell holds the CWA no-data sentinel (<= -90), so callers leave
// precipitation unset rather than recording a bogus value.
func gridPrecipitation(vals []float64, dimX int, startLon, startLat, res, lon, lat float64) *float64 {
	x := int(math.Round((lon - startLon) / res))
	y := int(math.Round((lat - startLat) / res))
	if x < 0 || y < 0 || x >= dimX || y*dimX+x >= len(vals) {
		return nil
	}
	v := vals[y*dimX+x]
	if v <= -90 {
		return nil
	}
	return &v
}

// weatherSync fetches current weather from two CWA datasets and caches a merged
// per-city snapshot in Redis (weather:<city>, 15-minute TTL) for ETA prediction.
// O-A0003-001 supplies station observations (temperature, wind, humidity), taking
// the most recent station per city; F-B0046-001 supplies a precipitation grid
// sampled per city. No-op when CWA_API_KEY is unset; a failure of either dataset
// is logged and the other's data is still cached.
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

	var grid struct {
		Cwaopendata struct {
			Dataset struct {
				DatasetInfo struct {
					ParameterSet struct {
						StartPointLongitude string `json:"StartPointLongitude"`
						StartPointLatitude  string `json:"StartPointLatitude"`
						GridResolution      string `json:"GridResolution"`
						GridDimensionX      string `json:"GridDimensionX"`
					} `json:"parameterSet"`
				} `json:"datasetInfo"`
				Contents struct {
					Content string `json:"content"`
				} `json:"contents"`
			} `json:"dataset"`
		} `json:"cwaopendata"`
	}
	resp2, err2 := client.R().SetHeader("Authorization", cwaKey).
		Get(cwaBase + "/F-B0046-001")
	if err2 == nil && resp2.StatusCode() == 200 {
		if jsonErr := json.Unmarshal(resp2.Body(), &grid); jsonErr == nil {
			ps := grid.Cwaopendata.Dataset.DatasetInfo.ParameterSet
			startLon, _ := strconv.ParseFloat(ps.StartPointLongitude, 64)
			startLat, _ := strconv.ParseFloat(ps.StartPointLatitude, 64)
			res, _ := strconv.ParseFloat(ps.GridResolution, 64)
			dimX, _ := strconv.Atoi(ps.GridDimensionX)
			if res <= 0 || dimX <= 0 {
				log.Infof("[WEATHER] F-B0046-001 invalid grid params, skipping")
			} else {
				parts := strings.Split(grid.Cwaopendata.Dataset.Contents.Content, ",")
				vals := make([]float64, len(parts))
				for i, p := range parts {
					raw := strings.TrimSpace(p)
					v, err := strconv.ParseFloat(raw, 64)
					if err != nil {
						log.Infof("[WEATHER] F-B0046-001 parse skipped raw=%s error=%v", raw, err)
						continue
					}
					vals[i] = v
				}
				for city, coords := range cityCoords {
					p := gridPrecipitation(vals, dimX, startLon, startLat, res, coords[1], coords[0])
					d := merged[city]
					if p != nil {
						d.Precipitation = *p
					}
					merged[city] = d
				}
			}
		}
	} else if err2 != nil {
		log.Infof("[WEATHER] F-B0046-001 fetch error: %v", err2)
	} else {
		log.Infof("[WEATHER] F-B0046-001 error status=%d", resp2.StatusCode())
	}

	for city, d := range merged {
		b, _ := json.Marshal(d)
		rc.Set(shared.WeatherKey(city), string(b), 15*time.Minute)
	}
	log.Infof("[WEATHER] synced %d cities", len(merged))
}
