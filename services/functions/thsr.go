package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"go.uber.org/zap"
	"google.golang.org/protobuf/proto"
)

// rawThsrAvailableSeatStatus decodes a TDX Rail/THSR/AvailableSeatStatus/Train
// element: one train's origin/destination seat-status segments for a date. Each
// top-level element carries an Items array of OD segments, aggregated per train
// into one ThsrAvailableSeats.
type rawThsrAvailableSeatStatus struct {
	TrainDate string `json:"TrainDate"`
	Items     []struct {
		TrainNo              string `json:"TrainNo"`
		OriginStationID      string `json:"OriginStationID"`
		DestinationStationID string `json:"DestinationStationID"`
		StandardSeatStatus   string `json:"StandardSeatStatus"`
		BusinessSeatStatus   string `json:"BusinessSeatStatus"`
	} `json:"Items"`
}

// thsrAvailableSeats refreshes the realtime THSR available-seat cache into Redis
// on the 10-minute cron (seats change slowly). It fetches today's
// AvailableSeatStatus feed for the Taipei calendar date, aggregates the OD
// segments per train into a ThsrAvailableSeats, and pipelines a SET under
// thsr_seats:<date>:<train> (15-minute TTL) plus a PUBLISH to the per-date
// channel so already-connected router streams get the update. On a 304 the
// runner has already re-armed the cached snapshots' TTL via boundFetch.
//
// This is the seat refresh ADR-0005 originally left on the router's read path;
// moving it here makes the router a pure reader (ADR-0005 amendment).
func thsrAvailableSeats(ctx context.Context, fetch boundFetch, sink liveSink) error {
	date := time.Now().In(_taipei).Format(time.DateOnly)
	zap.S().Infow("start", "component", "thsr_seats", "action", "thsr_seats", "event", "start", "date", date)
	result, err := fetch(ctx, fmt.Sprintf("/v2/Rail/THSR/AvailableSeatStatus/Train/OD/TrainDate/%s", date), "thsr_availableseats")
	if err != nil {
		return _oops.With("date", date).Wrapf(err, "fetch THSR available seats")
	}
	if !result.Modified {
		// A 304 has already re-armed the cached snapshots' TTL via boundFetch.
		zap.S().Warnw("skip",
			"component", "thsr_seats",
			"action", "thsr_seats",
			"event", "skip",
			"reason", "no_update",
		)
		return nil
	}
	err = commitTDXFetch(result, func(dec *json.Decoder) error {
		row := make(map[string]*models.ThsrAvailableSeats)
		if decErr := decodeLiveItems(dec, func(temp rawThsrAvailableSeatStatus) error {
			for _, stop := range temp.Items {
				if row[stop.TrainNo] == nil {
					row[stop.TrainNo] = &models.ThsrAvailableSeats{}
				}
				row[stop.TrainNo].Segments = append(row[stop.TrainNo].Segments, &models.ThsrSeatSegment{
					OriginStationId:      stop.OriginStationID,
					DestinationStationId: stop.DestinationStationID,
					StandardSeatStatus:   stop.StandardSeatStatus,
					BusinessSeatStatus:   stop.BusinessSeatStatus,
				})
			}
			return nil
		}); decErr != nil {
			return decErr
		}
		// The router's AvailableSeats stream subscribes to this same per-date string
		// (shared.ThsrSeatsPattern) as an opaque literal channel, so a plain PUBLISH
		// reaches it — no pattern semantics. It seeds new clients by SCANning the
		// per-train keys, so the SET keys carry the actual snapshots.
		channel := shared.ThsrSeatsPattern(date)
		pipe := sink.pipeline()
		count := 0
		for trainNo, seats := range row {
			pb, err := proto.Marshal(seats)
			if err != nil {
				return err
			}
			pipe.Set(shared.ThsrSeatsKey(date, trainNo), pb, _thsrSeatsLiveTTL)
			pipe.Publish(channel, string(pb))
			count++
		}
		if err := pipe.Exec(ctx); err != nil {
			return err
		}
		zap.S().Infow("complete",
			"component", "thsr_seats",
			"action", "thsr_seats",
			"event", "complete",
			"train_count", count,
		)
		return nil
	})
	if err != nil {
		return _oops.With("date", date).Wrapf(err, "process THSR available seats")
	}
	return nil
}
