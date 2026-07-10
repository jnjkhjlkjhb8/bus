package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type busEtaStore interface {
	staticStops(context.Context, string) ([]busStationmap, error)
	nextDepartures(context.Context, []routeDirKey, string, int) map[routeDirKey]time.Time
	travelAverages(context.Context, []string, int, int) map[travelAvgKey]int
	saveHistory(context.Context, [][]interface{})
	recordPredictions(context.Context, []predictionRecord)
}

type pgBusEtaStore struct {
	db *pgxpool.Pool
}

func (s pgBusEtaStore) staticStops(ctx context.Context, prefix string) ([]busStationmap, error) {
	return busstaticmp(ctx, s.db, prefix)
}

func (s pgBusEtaStore) nextDepartures(ctx context.Context, keys []routeDirKey, todTime string, dayBit int) map[routeDirKey]time.Time {
	return batchNextDepartures(ctx, s.db, keys, todTime, dayBit)
}

func (s pgBusEtaStore) travelAverages(ctx context.Context, uids []string, hour, dayOfWeek int) map[travelAvgKey]int {
	return batchTravelAvg(ctx, s.db, uids, hour, dayOfWeek)
}

func (s pgBusEtaStore) saveHistory(ctx context.Context, rows [][]interface{}) {
	saveBusEtaHistory(ctx, s.db, rows)
}

func (s pgBusEtaStore) recordPredictions(ctx context.Context, rows []predictionRecord) {
	recordPredictionErrors(ctx, s.db, rows)
}
