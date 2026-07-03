package main

import (
	"testing"
	"time"
)

func TestIsHolidayFallback(t *testing.T) {
	holidayMap = nil
	sat := time.Date(2026, 6, 13, 12, 0, 0, 0, taipei)
	sun := time.Date(2026, 6, 14, 12, 0, 0, 0, taipei)
	mon := time.Date(2026, 6, 15, 12, 0, 0, 0, taipei)
	if !isHoliday(sat) {
		t.Error("Saturday should be holiday")
	}
	if !isHoliday(sun) {
		t.Error("Sunday should be holiday")
	}
	if isHoliday(mon) {
		t.Error("Monday should not be holiday")
	}
}

func TestIsHolidayFromMap(t *testing.T) {
	holidayMap = map[string]bool{
		"2026-01-01": true,
		"2026-06-15": false,
	}
	newYear := time.Date(2026, 1, 1, 12, 0, 0, 0, taipei)
	monday := time.Date(2026, 6, 15, 12, 0, 0, 0, taipei)
	if !isHoliday(newYear) {
		t.Error("New Year should be holiday")
	}
	if isHoliday(monday) {
		t.Error("Normal Monday should not be holiday")
	}
	holidayMap = nil
}
