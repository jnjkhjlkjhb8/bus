package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/go-redis/redis"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
)

const cwaBase = "https://opendata.cwa.gov.tw/api/v1/rest/datastore"

const weatherHTTPTimeout = 30 * time.Second

type weatherData struct {
	Temperature   float64 `json:"temperature"`
	Precipitation float64 `json:"precipitation"`
	WindSpeed     float64 `json:"wind_speed"`
	Humidity      float64 `json:"humidity"`
}

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

func weatherSync(ctx context.Context, rc *redis.Client) error {
	apiKey := os.Getenv("CWA_API_KEY")
	if apiKey == "" {
		log.Warnf("[WEATHER] CWA_API_KEY not set, skipping")
		return nil
	}
	if rc == nil {
		return errors.New("weather Redis client is nil")
	}
	client := &http.Client{Timeout: weatherHTTPTimeout}
	snapshot, err := fetchWeatherSnapshot(ctx, client, cwaBase, apiKey)
	if err != nil {
		return err
	}
	return writeWeatherSnapshot(ctx, rc, snapshot)
}

func writeWeatherSnapshot(ctx context.Context, rc *redis.Client, snapshot map[string]weatherData) error {
	pipe := rc.WithContext(ctx).TxPipeline()
	for city, data := range snapshot {
		encoded, err := json.Marshal(data)
		if err != nil {
			return fmt.Errorf("marshal weather for %s: %w", city, err)
		}
		pipe.Set(shared.WeatherKey(city), encoded, time.Hour)
	}
	if _, err := pipe.Exec(); err != nil {
		return fmt.Errorf("write weather snapshot to Redis: %w", err)
	}
	log.Infof("[WEATHER] synced %d cities", len(snapshot))
	return nil
}

func fetchWeatherSnapshot(ctx context.Context, client *http.Client, baseURL, apiKey string) (map[string]weatherData, error) {
	if ctx == nil {
		return nil, errors.New("weather context is nil")
	}
	if client == nil {
		return nil, errors.New("weather HTTP client is nil")
	}
	obsBody, err := fetchCWA(ctx, client, baseURL+"/O-A0003-001", apiKey)
	if err != nil {
		return nil, fmt.Errorf("fetch observations: %w", err)
	}
	rainBody, err := fetchCWA(ctx, client, baseURL+"/O-A0002-001", apiKey)
	if err != nil {
		return nil, fmt.Errorf("fetch rainfall: %w", err)
	}
	observations, err := parseObservations(obsBody)
	if err != nil {
		return nil, fmt.Errorf("parse observations: %w", err)
	}
	rainfall, err := parseRainfall(rainBody)
	if err != nil {
		return nil, fmt.Errorf("parse rainfall: %w", err)
	}
	for city, precipitation := range rainfall {
		data, ok := observations[city]
		if !ok {
			continue
		}
		data.Precipitation = precipitation
		observations[city] = data
	}
	if len(observations) == 0 {
		return nil, errors.New("weather snapshot contains no usable cities")
	}
	return observations, nil
}

func fetchCWA(ctx context.Context, client *http.Client, url, apiKey string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", apiKey)
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request %s: %w", url, err)
	}
	defer resp.Body.Close()
	body, readErr := io.ReadAll(resp.Body)
	if readErr != nil {
		return nil, fmt.Errorf("read %s body: %w", url, readErr)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("request %s: HTTP status %d", url, resp.StatusCode)
	}
	return body, nil
}

type observationResponse struct {
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

func parseObservations(body []byte) (map[string]weatherData, error) {
	var payload observationResponse
	if err := decodeWeatherJSON(body, &payload); err != nil {
		return nil, err
	}
	type best struct {
		time time.Time
		data weatherData
	}
	latest := make(map[string]best)
	for _, station := range payload.Records.Station {
		city, ok := countyToCity[station.GeoInfo.CountyName]
		if !ok {
			continue
		}
		observedAt, err := time.Parse(time.RFC3339, station.ObsTime.DateTime)
		if err != nil {
			return nil, fmt.Errorf("city %s observation time: %w", city, err)
		}
		if previous, exists := latest[city]; exists && !observedAt.After(previous.time) {
			continue
		}
		temperature, err := parseCWAValue(station.WeatherElement.AirTemperature, "temperature")
		if err != nil {
			return nil, fmt.Errorf("city %s: %w", city, err)
		}
		wind, err := parseCWAValue(station.WeatherElement.WindSpeed, "wind speed")
		if err != nil {
			return nil, fmt.Errorf("city %s: %w", city, err)
		}
		humidity, err := parseCWAValue(station.WeatherElement.RelativeHumidity, "humidity")
		if err != nil {
			return nil, fmt.Errorf("city %s: %w", city, err)
		}
		if temperature < -90 || wind < -90 || humidity < -90 {
			continue
		}
		latest[city] = best{time: observedAt, data: weatherData{Temperature: temperature, WindSpeed: wind, Humidity: humidity}}
	}
	out := make(map[string]weatherData, len(latest))
	for city, value := range latest {
		out[city] = value.data
	}
	return out, nil
}

type rainfallResponse struct {
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

func parseRainfall(body []byte) (map[string]float64, error) {
	var payload rainfallResponse
	if err := decodeWeatherJSON(body, &payload); err != nil {
		return nil, err
	}
	type best struct {
		time  time.Time
		value float64
	}
	latest := make(map[string]best)
	for _, station := range payload.Records.Station {
		city, ok := countyToCity[station.GeoInfo.CountyName]
		if !ok {
			continue
		}
		observedAt, err := time.Parse(time.RFC3339, station.ObsTime.DateTime)
		if err != nil {
			return nil, fmt.Errorf("city %s rainfall time: %w", city, err)
		}
		value, err := parseCWAValue(station.RainfallElement.Now.Precipitation, "precipitation")
		if err != nil {
			return nil, fmt.Errorf("city %s: %w", city, err)
		}
		if value < 0 {
			continue
		}
		if previous, exists := latest[city]; !exists || observedAt.After(previous.time) {
			latest[city] = best{time: observedAt, value: value}
		}
	}
	out := make(map[string]float64, len(latest))
	for city, value := range latest {
		out[city] = value.value
	}
	return out, nil
}

func parseCWAValue(raw, field string) (float64, error) {
	value, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return 0, fmt.Errorf("parse %s %q: %w", field, raw, err)
	}
	return value, nil
}

func decodeWeatherJSON(body []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(body))
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return errors.New("JSON body contains trailing data")
		}
		return err
	}
	return nil
}
