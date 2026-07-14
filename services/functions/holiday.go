package main

import (
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
)

const holidayCSVURL = "https://data.ntpc.gov.tw/api/datasets/308dcd75-6434-45bc-a95f-584da4fed251/csv/file"

const holidayHTTPTimeout = 15 * time.Second

type holidaySnapshot struct {
	dates map[string]bool
}

var currentHolidaySnapshot atomic.Pointer[holidaySnapshot]

var taipei *time.Location

func init() {
	var err error
	taipei, err = time.LoadLocation("Asia/Taipei")
	if err != nil {
		panic("cannot load Asia/Taipei: " + err.Error())
	}
}

// loadHolidays fetches one complete immutable snapshot. The atomic pointer is
// swapped only after status, body, and CSV validation succeed, preserving the
// last good snapshot across transient refresh failures.
func loadHolidays(ctx context.Context) error {
	client := &http.Client{Timeout: holidayHTTPTimeout}
	return refreshHolidays(ctx, client, holidayCSVURL)
}

func refreshHolidays(ctx context.Context, client *http.Client, url string) error {
	if ctx == nil {
		return errors.New("holiday refresh context is nil")
	}
	if client == nil {
		return errors.New("holiday HTTP client is nil")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("create holiday request: %w", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("fetch holiday CSV: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		_, drainErr := io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
		return errors.Join(fmt.Errorf("fetch holiday CSV: HTTP status %d", resp.StatusCode), drainErr)
	}
	dates, err := parseHolidayCSV(resp.Body)
	if err != nil {
		return fmt.Errorf("parse holiday CSV: %w", err)
	}
	currentHolidaySnapshot.Store(&holidaySnapshot{dates: dates})
	log.Infof("[HOLIDAY] loaded %d entries", len(dates))
	return nil
}

func parseHolidayCSV(r io.Reader) (map[string]bool, error) {
	csvReader := csv.NewReader(r)
	if _, err := csvReader.Read(); err != nil {
		return nil, fmt.Errorf("read header: %w", err)
	}
	dates := make(map[string]bool)
	for {
		record, err := csvReader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("read row: %w", err)
		}
		if len(record) < 4 {
			return nil, fmt.Errorf("row has %d columns, want at least 4", len(record))
		}
		rawDate := strings.TrimSpace(record[0])
		date, err := time.Parse("20060102", rawDate)
		if err != nil {
			return nil, fmt.Errorf("date %q: %w", rawDate, err)
		}
		dates[date.Format(time.DateOnly)] = strings.TrimSpace(record[3]) == "是"
	}
	if len(dates) == 0 {
		return nil, errors.New("holiday CSV contains no data rows")
	}
	return dates, nil
}

func storeHolidaySnapshot(dates map[string]bool) {
	if dates == nil {
		currentHolidaySnapshot.Store(nil)
		return
	}
	copyOfDates := make(map[string]bool, len(dates))
	for date, holiday := range dates {
		copyOfDates[date] = holiday
	}
	currentHolidaySnapshot.Store(&holidaySnapshot{dates: copyOfDates})
}

// isHoliday first honors an explicit dataset entry, including weekend working
// days, then falls back to Saturday/Sunday when that date is absent.
func isHoliday(t time.Time) bool {
	local := t.In(taipei)
	if snapshot := currentHolidaySnapshot.Load(); snapshot != nil {
		if holiday, ok := snapshot.dates[local.Format(time.DateOnly)]; ok {
			return holiday
		}
	}
	return local.Weekday() == time.Saturday || local.Weekday() == time.Sunday
}
