package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// railStation decodes a TDX TRA/THSR Station element, used for both the TRA and
// THSR static station tables.
type railStation struct {
	StationID   string `json:"StationID"`
	StationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
	LocationCityCode string `json:"LocationCityCode"`
	StationPosition  struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationPosition"`
	StationCode string `json:"StationCode"`
}

// tra_fare decodes a TDX TRA/ODFare element: fares between a station pair by
// ticket type.
type tra_fare struct {
	OriginStationID      string `json:"OriginStationID"`
	DestinationStationID string `json:"DestinationStationID"`
	Fares                []struct {
		TicketType string `json:"TicketType"`
		Price      int32  `json:"Price"`
	} `json:"Fares"`
}

// thsr_fare decodes a TDX THSR/ODFare element: fares between a station pair,
// further split by fare class and cabin class.
type thsr_fare struct {
	OriginStationID      string `json:"OriginStationID"`
	DestinationStationID string `json:"DestinationStationID"`
	Fares                []struct {
		TicketType uint8  `json:"TicketType"`
		FareClass  uint8  `json:"FareClass"`
		CabinClass uint8  `json:"CabinClass"`
		Price      uint16 `json:"Price"`
	} `json:"Fares"`
}

// traDelay decodes a TDX TRA/LiveTrainDelay element: a train's current delay in
// minutes at a station.
type traDelay struct {
	TrainNo     string `json:"TrainNo"`
	StationID   string `json:"StationID"`
	StationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
	DelayTime     uint16 `json:"DelayTime"`
	SrcUpdateTime string `json:"SrcUpdateTime"`
}

// raw_tra_timetable decodes a TDX TRA/DailyTimetable element: one train's info
// and its ordered stop times for a given service date.
type raw_tra_timetable struct {
	TrainDate      string `json:"TrainDate"`
	DailyTrainInfo struct {
		TrainNo             string `json:"TrainNo"`
		Direction           *uint8 `json:"Direction"`
		StartingStationID   string `json:"StartingStationID"`
		StartingStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StartingStationName"`
		EndingStationID   string `json:"EndingStationID"`
		EndingStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"EndingStationName"`
		TrainTypeID   string `json:"TrainTypeID"`
		TrainTypeCode string `json:"TrainTypeCode"`
		TrainTypeName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"TrainTypeName"`
		TripLine           uint8  `json:"TripLine"`
		WheelchairFlag     *uint8 `json:"WheelchairFlag"`
		PackageServiceFlag *uint8 `json:"PackageServiceFlag"`
		DiningFlag         *uint8 `json:"DiningFlag"`
		BikeFlag           *uint8 `json:"BikeFlag"`
		BreastFeedingFlag  *uint8 `json:"BreastFeedingFlag"`
		DailyFlag          *uint8 `json:"DailyFlag"`
		ServiceAddedFlag   *uint8 `json:"ServiceAddedFlag"`
		SuspendedFlag      *uint8 `json:"SuspendedFlag"`
		Note               struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"Note"`
	} `json:"DailyTrainInfo"`
	StopTimes []struct {
		StopSequence uint8  `json:"StopSequence"`
		StationID    string `json:"StationID"`
		StationName  struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StationName"`
		ArrivalTime   string `json:"ArrivalTime"`
		DepartureTime string `json:"DepartureTime"`
		SuspendedFlag *uint8 `json:"SuspendedFlag"`
	} `json:"StopTimes"`
}

// raw_thsr_timetable decodes a TDX THSR/DailyTimetable element: one high-speed
// train's info and stop times for a service date. Overnight marks a train that
// crosses midnight.
type raw_thsr_timetable struct {
	TrainDate      string `json:"TrainDate"`
	DailyTrainInfo struct {
		TrainNo             string `json:"TrainNo"`
		Direction           *uint8 `json:"Direction"`
		StartingStationID   string `json:"StartingStationID"`
		StartingStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StartingStationName"`
		EndingStationID   string `json:"EndingStationID"`
		EndingStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"EndingStationName"`
		Note struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"Note"`
		Overnight *bool `json:"Overnight"`
	} `json:"DailyTrainInfo"`
	StopTimes []struct {
		StopSequence uint8  `json:"StopSequence"`
		StationID    string `json:"StationID"`
		StationName  struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StationName"`
		ArrivalTime   string `json:"ArrivalTime"`
		DepartureTime string `json:"DepartureTime"`
	} `json:"StopTimes"`
}

// railTrainFlags holds a TRA train's amenity/service boolean flags (1 = set)
// before they are packed into a single bitmask by railMask.
type railTrainFlags struct {
	wheel     uint8
	pack      uint8
	dining    uint8
	bike      uint8
	breast    uint8
	daily     uint8
	service   uint8
	suspended uint8
}

// railMask packs a TRA train's amenity flags into a uint16 bitmask (bit 0 =
// wheelchair through bit 7 = suspended, in struct field order) for compact
// storage in tra_timetable.mask.
func railMask(f railTrainFlags) uint16 {
	var res uint16
	for i, v := range []uint8{f.wheel, f.pack, f.dining, f.bike, f.breast, f.daily, f.service, f.suspended} {
		if v == 1 {
			res |= 1 << i
		}
	}
	return res
}

func validateBinaryFlag(field string, value uint8) error {
	if value > 1 {
		return fmt.Errorf("%s must be 0 or 1, got %d", field, value)
	}
	return nil
}

func requiredBinaryFlag(field string, value *uint8) (uint8, error) {
	if value == nil {
		return 0, fmt.Errorf("%s is required", field)
	}
	if err := validateBinaryFlag(field, *value); err != nil {
		return 0, err
	}
	return *value, nil
}

func validateTraTimetable(timetable raw_tra_timetable, partitionDate string) error {
	trainDate := timetable.TrainDate
	if trainDate == "" {
		trainDate = partitionDate
	}
	if _, err := time.Parse(time.DateOnly, trainDate); err != nil {
		return fmt.Errorf("TrainDate %q: %w", trainDate, err)
	}
	if trainDate != partitionDate {
		return fmt.Errorf("TrainDate %q does not match partition date %q", trainDate, partitionDate)
	}
	info := timetable.DailyTrainInfo
	if strings.TrimSpace(info.TrainNo) == "" {
		return errors.New("TrainNo is required")
	}
	if strings.TrimSpace(info.StartingStationID) == "" {
		return errors.New("StartingStationID is required")
	}
	if strings.TrimSpace(info.EndingStationID) == "" {
		return errors.New("EndingStationID is required")
	}
	if info.Direction == nil {
		return errors.New("Direction is required")
	}
	if *info.Direction > 1 {
		return fmt.Errorf("Direction must be 0 or 1, got %d", *info.Direction)
	}
	for _, flag := range []struct {
		name  string
		value *uint8
	}{
		{"WheelchairFlag", info.WheelchairFlag},
		{"PackageServiceFlag", info.PackageServiceFlag},
		{"DiningFlag", info.DiningFlag},
		{"BikeFlag", info.BikeFlag},
		{"BreastFeedingFlag", info.BreastFeedingFlag},
		{"DailyFlag", info.DailyFlag},
		{"ServiceAddedFlag", info.ServiceAddedFlag},
		{"SuspendedFlag", info.SuspendedFlag},
	} {
		if _, err := requiredBinaryFlag(flag.name, flag.value); err != nil {
			return err
		}
	}
	if len(timetable.StopTimes) == 0 {
		return errors.New("StopTimes must not be empty")
	}
	for index, stop := range timetable.StopTimes {
		if stop.StopSequence == 0 {
			return fmt.Errorf("StopTimes element %d StopSequence must be positive", index)
		}
		if strings.TrimSpace(stop.StationID) == "" {
			return fmt.Errorf("StopTimes element %d StationID is required", index)
		}
		if !validClock(stop.ArrivalTime) {
			return fmt.Errorf("StopTimes element %d ArrivalTime is invalid: %q", index, stop.ArrivalTime)
		}
		if !validClock(stop.DepartureTime) {
			return fmt.Errorf("StopTimes element %d DepartureTime is invalid: %q", index, stop.DepartureTime)
		}
		if _, err := requiredBinaryFlag("SuspendedFlag", stop.SuspendedFlag); err != nil {
			return fmt.Errorf("StopTimes element %d: %w", index, err)
		}
	}
	return nil
}

func validateThsrTimetable(timetable raw_thsr_timetable, partitionDate string) error {
	if _, err := time.Parse(time.DateOnly, timetable.TrainDate); err != nil {
		return fmt.Errorf("TrainDate %q: %w", timetable.TrainDate, err)
	}
	if timetable.TrainDate != partitionDate {
		return fmt.Errorf("TrainDate %q does not match partition date %q", timetable.TrainDate, partitionDate)
	}
	info := timetable.DailyTrainInfo
	if strings.TrimSpace(info.TrainNo) == "" {
		return errors.New("TrainNo is required")
	}
	if strings.TrimSpace(info.StartingStationID) == "" {
		return errors.New("StartingStationID is required")
	}
	if strings.TrimSpace(info.EndingStationID) == "" {
		return errors.New("EndingStationID is required")
	}
	if info.Direction == nil {
		return errors.New("Direction is required")
	}
	if *info.Direction > 1 {
		return fmt.Errorf("Direction must be 0 or 1, got %d", *info.Direction)
	}
	if info.Overnight == nil {
		return errors.New("Overnight is required")
	}
	if len(timetable.StopTimes) == 0 {
		return errors.New("StopTimes must not be empty")
	}
	for index, stop := range timetable.StopTimes {
		if stop.StopSequence == 0 {
			return fmt.Errorf("StopTimes element %d StopSequence must be positive", index)
		}
		if strings.TrimSpace(stop.StationID) == "" {
			return fmt.Errorf("StopTimes element %d StationID is required", index)
		}
		if !validClock(stop.ArrivalTime) {
			return fmt.Errorf("StopTimes element %d ArrivalTime is invalid: %q", index, stop.ArrivalTime)
		}
		if !validClock(stop.DepartureTime) {
			return fmt.Errorf("StopTimes element %d DepartureTime is invalid: %q", index, stop.DepartureTime)
		}
	}
	return nil
}

// loadTraTimetable upserts one day's TRA daily timetable stop rows into
// tra_timetable via a temp-table COPY. Stop times are validated and parsed as
// "15:04" before any sink call. It consumes an already-opened decoder; the
// temp_tra_timetable drain upserts by (train_date,trainno,stationid), with the
// train-wide and stop-wide suspension flags combined in the stored stop mask.
func loadTraTimetable(ctx context.Context, dec *json.Decoder, sink loadSink, date string) error {
	if _, err := time.Parse(time.DateOnly, date); err != nil {
		return fmt.Errorf("TRA timetable partition date %q: %w", date, err)
	}
	timetables, err := decodeLoadArray[raw_tra_timetable](dec, "TRA timetable "+date, func(_ int, timetable raw_tra_timetable) error {
		return validateTraTimetable(timetable, date)
	})
	if err != nil {
		return err
	}
	row := [][]any{}
	seen := make(map[string][]any)
	for _, temp := range timetables {
		if temp.TrainDate == "" {
			temp.TrainDate = date
		}
		for _, stop := range temp.StopTimes {
			at, err := time.Parse("15:04", stop.ArrivalTime)
			if err != nil {
				return fmt.Errorf("TRA timetable %s train %q station %q ArrivalTime %q: %w", date, temp.DailyTrainInfo.TrainNo, stop.StationID, stop.ArrivalTime, err)
			}
			dt, err := time.Parse("15:04", stop.DepartureTime)
			if err != nil {
				return fmt.Errorf("TRA timetable %s train %q station %q DepartureTime %q: %w", date, temp.DailyTrainInfo.TrainNo, stop.StationID, stop.DepartureTime, err)
			}
			candidate := []any{
				temp.TrainDate,
				temp.DailyTrainInfo.TrainNo,
				*temp.DailyTrainInfo.Direction,
				temp.DailyTrainInfo.StartingStationID,
				temp.DailyTrainInfo.StartingStationName.ZhTw,
				temp.DailyTrainInfo.EndingStationID,
				temp.DailyTrainInfo.EndingStationName.ZhTw,
				temp.DailyTrainInfo.TrainTypeID,
				temp.DailyTrainInfo.TrainTypeCode,
				temp.DailyTrainInfo.TrainTypeName.ZhTw,
				temp.DailyTrainInfo.TripLine,
				stop.StopSequence,
				stop.StationID,
				stop.StationName.ZhTw,
				at,
				dt,
				railMask(railTrainFlags{
					wheel:     *temp.DailyTrainInfo.WheelchairFlag,
					pack:      *temp.DailyTrainInfo.PackageServiceFlag,
					dining:    *temp.DailyTrainInfo.DiningFlag,
					bike:      *temp.DailyTrainInfo.BikeFlag,
					breast:    *temp.DailyTrainInfo.BreastFeedingFlag,
					daily:     *temp.DailyTrainInfo.DailyFlag,
					service:   *temp.DailyTrainInfo.ServiceAddedFlag,
					suspended: *temp.DailyTrainInfo.SuspendedFlag | *stop.SuspendedFlag,
				}),
				temp.DailyTrainInfo.Note.ZhTw,
			}
			key := temp.TrainDate + "\x00" + temp.DailyTrainInfo.TrainNo + "\x00" + stop.StationID
			if err := appendUniqueLoadRow(&row, seen, key, "timetable", candidate); err != nil {
				return fmt.Errorf("TRA timetable %s: %w", date, err)
			}
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key:     "tra_timetable",
		preExec: []copyUpsertStmt{{sql: `DELETE FROM tra_timetable WHERE train_date = $1`, args: []any{date}}},
		createSQL: `CREATE TEMP TABLE temp_tra_timetable (
				train_date            date not null,
				trainno               text not null,
				direction             integer,
				starting_station_id   text not null,
				starting_station_name text not null,
				ending_station_id     text not null,
				ending_station_name   text not null,
				train_type_id         text,
				train_type_code       text,
				train_type_name       text,
				tripline              integer,
				stopsequence          smallint,
				stationid             text,
				stationname           text,
				arrivaltime           time,
				departuretime         time,
				mask                  smallint,
				note                  text,
				updated_at            timestamp with time zone
			) ON COMMIT DROP;`,
		tempTable: "temp_tra_timetable",
		copyCols: []string{
			"train_date", "trainno", "direction", "starting_station_id", "starting_station_name",
			"ending_station_id", "ending_station_name", "train_type_id", "train_type_code", "train_type_name",
			"tripline", "stopsequence", "stationid", "stationname", "arrivaltime", "departuretime", "mask", "note",
		},
		insertSQL: `INSERT INTO tra_timetable (
			train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,train_type_id,train_type_code,train_type_name,
			tripline,stopsequence,stationid,stationname,arrivaltime,departuretime,mask,note,updated_at
		)
		SELECT train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,train_type_id,train_type_code,train_type_name,
			tripline,stopsequence,stationid,stationname,arrivaltime,departuretime,mask,note,NOW()
		FROM temp_tra_timetable
		ON CONFLICT (train_date,trainno,stationid) DO UPDATE SET
			direction=EXCLUDED.direction, starting_station_id=EXCLUDED.starting_station_id,
			starting_station_name=EXCLUDED.starting_station_name, ending_station_name=EXCLUDED.ending_station_name,
			ending_station_id=EXCLUDED.ending_station_id, train_type_id=EXCLUDED.train_type_id,
			train_type_code=EXCLUDED.train_type_code, train_type_name=EXCLUDED.train_type_name,
			tripline=EXCLUDED.tripline, stopsequence=EXCLUDED.stopsequence, stationname=EXCLUDED.stationname,
			arrivaltime=EXCLUDED.arrivaltime, departuretime=EXCLUDED.departuretime,
			mask=EXCLUDED.mask, note=EXCLUDED.note, updated_at=NOW();`,
	}, row)
}

// loadThsrTimetable upserts one day's THSR daily timetable stop rows into
// thsr_timetable via a temp-table COPY. Stop times are validated and parsed as
// "15:04" before any sink call. It consumes an already-opened decoder;
// the temp_thsr_timetable COPY and ON CONFLICT (train_date,trainno,stationid)
// upsert are byte-identical to the legacy transform.
func loadThsrTimetable(ctx context.Context, dec *json.Decoder, sink loadSink, date string) error {
	if _, err := time.Parse(time.DateOnly, date); err != nil {
		return fmt.Errorf("THSR timetable partition date %q: %w", date, err)
	}
	timetables, err := decodeLoadArray[raw_thsr_timetable](dec, "THSR timetable "+date, func(_ int, timetable raw_thsr_timetable) error {
		return validateThsrTimetable(timetable, date)
	})
	if err != nil {
		return err
	}
	row := [][]any{}
	seen := make(map[string][]any)
	for _, temp := range timetables {
		for _, stop := range temp.StopTimes {
			at, err := time.Parse("15:04", stop.ArrivalTime)
			if err != nil {
				return fmt.Errorf("THSR timetable %s train %q station %q ArrivalTime %q: %w", date, temp.DailyTrainInfo.TrainNo, stop.StationID, stop.ArrivalTime, err)
			}
			dt, err := time.Parse("15:04", stop.DepartureTime)
			if err != nil {
				return fmt.Errorf("THSR timetable %s train %q station %q DepartureTime %q: %w", date, temp.DailyTrainInfo.TrainNo, stop.StationID, stop.DepartureTime, err)
			}
			candidate := []any{
				temp.TrainDate,
				temp.DailyTrainInfo.TrainNo,
				*temp.DailyTrainInfo.Direction,
				temp.DailyTrainInfo.StartingStationID,
				temp.DailyTrainInfo.StartingStationName.ZhTw,
				temp.DailyTrainInfo.EndingStationID,
				temp.DailyTrainInfo.EndingStationName.ZhTw,
				stop.StopSequence,
				stop.StationID,
				stop.StationName.ZhTw,
				at,
				dt,
				temp.DailyTrainInfo.Note.ZhTw,
				*temp.DailyTrainInfo.Overnight,
			}
			key := temp.TrainDate + "\x00" + temp.DailyTrainInfo.TrainNo + "\x00" + stop.StationID
			if err := appendUniqueLoadRow(&row, seen, key, "timetable", candidate); err != nil {
				return fmt.Errorf("THSR timetable %s: %w", date, err)
			}
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key:     "thsr_timetable",
		preExec: []copyUpsertStmt{{sql: `DELETE FROM thsr_timetable WHERE train_date = $1`, args: []any{date}}},
		createSQL: `CREATE TEMP TABLE temp_thsr_timetable (
				train_date            date not null,
				trainno               text not null,
				direction             integer,
				starting_station_id   text not null,
				starting_station_name text not null,
				ending_station_id     text not null,
				ending_station_name   text not null,
				stopsequence          smallint,
				stationid             text,
				stationname           text,
				arrivaltime           time,
				departuretime         time,
				note                  text,
				overnight             boolean,
				updated_at            timestamp with time zone
			) ON COMMIT DROP;`,
		tempTable: "temp_thsr_timetable",
		copyCols: []string{
			"train_date", "trainno", "direction", "starting_station_id", "starting_station_name",
			"ending_station_id", "ending_station_name", "stopsequence", "stationid", "stationname",
			"arrivaltime", "departuretime", "note", "overnight",
		},
		insertSQL: `INSERT INTO thsr_timetable (
			train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,stopsequence,stationid,stationname,
			arrivaltime,departuretime,note,overnight,updated_at
		)
		SELECT train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,stopsequence,stationid,stationname,
			arrivaltime,departuretime,note,overnight,NOW()
		FROM temp_thsr_timetable
		ON CONFLICT (train_date,trainno,stationid) DO UPDATE SET
			direction=EXCLUDED.direction, starting_station_id=EXCLUDED.starting_station_id,
			starting_station_name=EXCLUDED.starting_station_name, ending_station_name=EXCLUDED.ending_station_name,
			ending_station_id=EXCLUDED.ending_station_id, stopsequence=EXCLUDED.stopsequence,
			stationname=EXCLUDED.stationname, arrivaltime=EXCLUDED.arrivaltime,
			departuretime=EXCLUDED.departuretime, note=EXCLUDED.note, overnight=EXCLUDED.overnight, updated_at=NOW();`,
	}, row)
}

// loadTraStation upserts TRA stations into tra_stations via a temp-table COPY,
// resolving the city from the station's LocationCityCode prefix. It consumes an
// already-opened decoder (the raw_tdx loader reconstructs it); the temp-table
// COPY and ON CONFLICT (station_id) upsert are byte-identical to the legacy
// transform. It returns the first hard error instead of logging-and-returning.
func loadTraStation(ctx context.Context, dec *json.Decoder, sink loadSink, _ string) error {
	stations, err := decodeLoadArray[railStation](dec, "TRA stations", func(_ int, station railStation) error {
		return validateRailStation(station, false)
	})
	if err != nil {
		return err
	}
	row := [][]any{}
	seen := make(map[string][]any, len(stations))
	for _, temp := range stations {
		g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
		candidate := []any{
			temp.StationID,
			temp.StationName.ZhTw,
			citymap2[temp.LocationCityCode],
			g,
		}
		if err := appendUniqueLoadRow(&row, seen, temp.StationID, "station", candidate); err != nil {
			return fmt.Errorf("TRA stations: %w", err)
		}
	}
	if len(row) > 0 {
		if err := sink.copyUpsert(ctx, copyUpsertSpec{
			key: "tra_station",
			createSQL: `CREATE TEMP TABLE temp_tra (
					station_id text,
					name text,
					city text,
					geom text
				) ON COMMIT DROP;`,
			tempTable: "temp_tra",
			copyCols:  []string{"station_id", "name", "city", "geom"},
			insertSQL: `INSERT INTO tra_stations (
					station_id,
					name,
					city,
					geom,
					updated_at
				)
				SELECT station_id, name, city, ST_GeomFromText(geom, 4326),NOW()
				FROM temp_tra
				ON CONFLICT (station_id) DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city, geom = EXCLUDED.geom,updated_at = NOW();`,
		}, row); err != nil {
			return err
		}
	} else {
		log.Infof("[RAIL] action=tra_station event=complete reason=no_data")
	}
	log.Infof("[RAIL] action=tra_station event=complete")
	return nil
}

// loadThsrStation upserts THSR stations into thsr_stations via one temp-table
// COPY transaction. It consumes an already-opened decoder and rejects an
// invalid or ambiguous payload before opening the transaction.
func loadThsrStation(ctx context.Context, dec *json.Decoder, sink copyUpsertSink, _ string) error {
	stations, err := decodeLoadArray[railStation](dec, "THSR stations", func(_ int, station railStation) error {
		return validateRailStation(station, true)
	})
	if err != nil {
		return err
	}
	if len(stations) == 0 {
		return nil
	}
	rows := make([][]any, 0, len(stations))
	seen := make(map[string][]any, len(stations))
	for _, station := range stations {
		g := fmt.Sprintf("POINT(%.6f %.6f)", station.StationPosition.PositionLon, station.StationPosition.PositionLat)
		candidate := []any{
			station.StationID,
			station.StationName.ZhTw,
			citymap2[station.LocationCityCode],
			g,
			station.StationCode,
		}
		if err := appendUniqueLoadRow(&rows, seen, station.StationID, "station", candidate); err != nil {
			return fmt.Errorf("THSR stations: %w", err)
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "thsr_station",
		createSQL: `CREATE TEMP TABLE temp_thsr_station (
			station_id text, name text, city text, geom text, stationcode text
		) ON COMMIT DROP`,
		tempTable: "temp_thsr_station",
		copyCols:  []string{"station_id", "name", "city", "geom", "stationcode"},
		insertSQL: `INSERT INTO thsr_stations (
			station_id, name, city, geom, stationcode, updated_at
		)
		SELECT station_id, name, city, ST_GeomFromText(geom, 4326), stationcode, NOW()
		FROM temp_thsr_station
		ON CONFLICT (station_id) DO UPDATE SET
			name = EXCLUDED.name, city = EXCLUDED.city, geom = EXCLUDED.geom,
			stationcode = EXCLUDED.stationcode, updated_at = NOW()`,
	}, rows)
}

func validateRailStation(station railStation, requireStationCode bool) error {
	if strings.TrimSpace(station.StationID) == "" {
		return errors.New("StationID is required")
	}
	if strings.TrimSpace(station.LocationCityCode) == "" {
		return errors.New("LocationCityCode is required")
	}
	if _, ok := citymap2[station.LocationCityCode]; !ok {
		return fmt.Errorf("LocationCityCode %q is unknown", station.LocationCityCode)
	}
	if requireStationCode && strings.TrimSpace(station.StationCode) == "" {
		return errors.New("StationCode is required")
	}
	if !validPosition(station.StationPosition.PositionLon, station.StationPosition.PositionLat) {
		return fmt.Errorf("position is invalid: lon=%v lat=%v", station.StationPosition.PositionLon, station.StationPosition.PositionLat)
	}
	return nil
}

// loadTraFare upserts the TRA OD fare table into tra_fares via a temp-table COPY,
// flattening each station pair's per-ticket-type fares into rows. It consumes an
// already-opened decoder; the temp_tra_fare COPY and ON CONFLICT
// (origin_station_id, destination_station_id, ticket_type) upsert are
// byte-identical to the legacy transform.
func loadTraFare(ctx context.Context, dec *json.Decoder, sink loadSink, _ string) error {
	fares, err := decodeLoadArray[tra_fare](dec, "TRA fares", func(_ int, fare tra_fare) error {
		if strings.TrimSpace(fare.OriginStationID) == "" {
			return errors.New("OriginStationID is required")
		}
		if strings.TrimSpace(fare.DestinationStationID) == "" {
			return errors.New("DestinationStationID is required")
		}
		if len(fare.Fares) == 0 {
			return errors.New("Fares must not be empty")
		}
		for index, item := range fare.Fares {
			if strings.TrimSpace(item.TicketType) == "" {
				return fmt.Errorf("Fares element %d TicketType is required", index)
			}
			if item.Price < 0 {
				return fmt.Errorf("Fares element %d Price must be non-negative", index)
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	if len(fares) == 0 {
		return nil
	}
	row := [][]any{}
	seen := make(map[string][]any)
	for _, temp := range fares {
		for _, t1 := range temp.Fares {
			candidate := []any{temp.OriginStationID, temp.DestinationStationID, t1.TicketType, t1.Price}
			key := temp.OriginStationID + "\x00" + temp.DestinationStationID + "\x00" + t1.TicketType
			if err := appendUniqueLoadRow(&row, seen, key, "fare", candidate); err != nil {
				return fmt.Errorf("TRA fares: %w", err)
			}
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "tra_fare",
		createSQL: `CREATE TEMP TABLE temp_tra_fare (
				origin_station_id text,
				destination_station_id text,
				ticket_type text,
				price int
			) ON COMMIT DROP;`,
		tempTable: "temp_tra_fare",
		copyCols:  []string{"origin_station_id", "destination_station_id", "ticket_type", "price"},
		insertSQL: `INSERT INTO tra_fares (
				origin_station_id,
				destination_station_id,
				ticket_type,
				price,
				updated_at
			)
			SELECT origin_station_id, destination_station_id, ticket_type, price, NOW() FROM temp_tra_fare
			ON CONFLICT (origin_station_id, destination_station_id, ticket_type)
			DO UPDATE SET price = EXCLUDED.price, updated_at = NOW()`,
	}, row)
}

// loadThsrFare upserts the THSR OD fare table into thsr_fares via a temp-table
// COPY, keyed by station pair plus ticket/fare/cabin class. It consumes an
// already-opened decoder; the temp_thsr COPY and ON CONFLICT
// (origin,destination,ticket_type,fare_class,cabin_class) upsert are
// byte-identical to the legacy transform.
func loadThsrFare(ctx context.Context, dec *json.Decoder, sink loadSink, _ string) error {
	fares, err := decodeLoadArray[thsr_fare](dec, "THSR fares", func(_ int, fare thsr_fare) error {
		if strings.TrimSpace(fare.OriginStationID) == "" {
			return errors.New("OriginStationID is required")
		}
		if strings.TrimSpace(fare.DestinationStationID) == "" {
			return errors.New("DestinationStationID is required")
		}
		if len(fare.Fares) == 0 {
			return errors.New("Fares must not be empty")
		}
		for index, item := range fare.Fares {
			if item.TicketType == 0 {
				return fmt.Errorf("Fares element %d TicketType is required", index)
			}
			if item.FareClass == 0 {
				return fmt.Errorf("Fares element %d FareClass is required", index)
			}
			if item.CabinClass == 0 {
				return fmt.Errorf("Fares element %d CabinClass is required", index)
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	if len(fares) == 0 {
		return nil
	}
	row := [][]any{}
	seen := make(map[string][]any)
	for _, temp := range fares {
		for _, t1 := range temp.Fares {
			candidate := []any{temp.OriginStationID, temp.DestinationStationID, t1.TicketType, t1.FareClass, t1.CabinClass, t1.Price}
			key := fmt.Sprintf("%s\x00%s\x00%d\x00%d\x00%d", temp.OriginStationID, temp.DestinationStationID, t1.TicketType, t1.FareClass, t1.CabinClass)
			if err := appendUniqueLoadRow(&row, seen, key, "fare", candidate); err != nil {
				return fmt.Errorf("THSR fares: %w", err)
			}
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "thsr_fare",
		createSQL: `CREATE TEMP TABLE temp_thsr (
				origin_station_id text,
				destination_station_id text,
				ticket_type smallint,
				fare_class smallint,
				cabin_class smallint,
				price int
			) ON COMMIT DROP;`,
		tempTable: "temp_thsr",
		copyCols:  []string{"origin_station_id", "destination_station_id", "ticket_type", "fare_class", "cabin_class", "price"},
		insertSQL: `INSERT INTO thsr_fares (
				origin_station_id,
				destination_station_id,
				ticket_type,
				fare_class,
				cabin_class,
				price,
				updated_at
			)
			SELECT origin_station_id, destination_station_id, ticket_type, fare_class,cabin_class,price, NOW() FROM temp_thsr
			ON CONFLICT (origin_station_id, destination_station_id, ticket_type, fare_class, cabin_class)
			DO UPDATE SET price = EXCLUDED.price, updated_at = NOW()`,
	}, row)
}

// traEta refreshes TRA realtime data into Redis on the 2-minute cron: per-train
// delays as hash tra:delay plus a published tra:delay:all snapshot, all with a
// 3-minute TTL so stale data expires.
func traEta(ctx context.Context, fetch boundFetch, sink liveSink) error {
	log.Infof("[TRA_ETA] action=tra_eta event=start")
	result, err := fetch(ctx, "/v2/Rail/TRA/LiveTrainDelay", "tra_delay")
	if err != nil {
		log.Infof("[TRA_ETA] action=tra_eta event=skip_delay reason=api_error error=%v", err)
		return err
	}
	if !result.Modified {
		// On a 304, boundFetch has already re-armed the delay keys' TTL.
		log.Infof("[TRA_ETA] action=tra_eta event=skip_delay reason=no_update")
		return nil
	}
	err = commitTDXFetch(result, func(dec *json.Decoder) error {
		data := &models.TraDelays{
			Delay: make(map[string]int32),
		}
		count := 0
		pipe := sink.pipeline()
		if decErr := decodeLiveItems(dec, func(temp traDelay) error {
			count++
			data.Delay[temp.TrainNo] = int32(temp.DelayTime)
			pipe.HSet(shared.TraDelayHashKey, temp.TrainNo, temp.DelayTime)
			return nil
		}); decErr != nil {
			return decErr
		}
		bytes, err := proto.Marshal(data)
		if err != nil {
			return err
		}
		pipe.Set(shared.TraDelayAllKey, bytes, traLiveTTL)
		pipe.Publish(shared.TraDelayAllKey, string(bytes))
		pipe.Expire(shared.TraDelayHashKey, traLiveTTL)
		if err := pipe.Exec(); err != nil {
			return err
		}
		log.Infof("[TRA_ETA] action=tra_eta event=delay_redis_success count=%d", count)
		return nil
	})
	if err != nil {
		log.Infof("[TRA_ETA] action=tra_eta event=process_error error=%v", err)
		return err
	}
	log.Infof("[TRA_ETA] action=tra_eta event=complete")
	return nil
}
