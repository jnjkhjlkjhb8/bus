import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/generated/mrt.pb.dart';
import 'package:wheres_the_car/data/generated/thsr.pb.dart';
import 'package:wheres_the_car/data/generated/tra.pb.dart';

/// Mock bus static route data shaped like the generated backend payload.
final mockBusSubroute = Bus_subroute(
  routeUID: 'TPE-307',
  routeName: '307',
  subRouteUID: 'TPE-307-main',
  subRouteName: '307',
  departureStopName: '板橋',
  destinationStopName: '撫遠街',
  city: 'Taipei',
  directions: [
    MapEntry(
      0,
      Direction(
        departureStopName: '板橋',
        destinationStopName: '撫遠街',
        stops: [
          Bus_stop(
            stopUID: 'TPE-307-001',
            stopName: '板橋公車站',
            stopSequence: 1,
            positionLon: 121.4628,
            positionLat: 25.0143,
            stationID: 'BL01',
          ),
          Bus_stop(
            stopUID: 'TPE-307-002',
            stopName: '西門町',
            stopSequence: 2,
            positionLon: 121.5074,
            positionLat: 25.0421,
            stationID: 'XM01',
          ),
        ],
      ),
    ),
    MapEntry(
      1,
      Direction(
        departureStopName: '撫遠街',
        destinationStopName: '板橋',
        stops: [
          Bus_stop(
            stopUID: 'TPE-307-101',
            stopName: '撫遠街',
            stopSequence: 1,
            positionLon: 121.5651,
            positionLat: 25.0596,
            stationID: 'FY01',
          ),
          Bus_stop(
            stopUID: 'TPE-307-102',
            stopName: '捷運西門站',
            stopSequence: 2,
            positionLon: 121.5082,
            positionLat: 25.0422,
            stationID: 'XM02',
          ),
        ],
      ),
    ),
  ],
);

/// Mock bus route arrivals shaped like the generated backend payload.
final mockBusRouteArrival = Bus_RouteArrival(
  subRouteUid: 'TPE-307-main',
  stops: [
    Bus_RouteEstimate(
      stopUid: 'TPE-307-001',
      direction: 0,
      estimate: 180,
      nextBusTime: '2026-06-18T08:15:00+08:00',
      stopStatus: 0,
      srcUpdateTime: '2026-06-18T08:12:00+08:00',
      buses: [
        Bus_position(
          plateNumb: 'KKA-307',
          positionLon: 121.4628,
          positionLat: 25.0143,
          speed: 24,
          azimuth: 87,
        ),
      ],
    ),
    Bus_RouteEstimate(
      stopUid: 'TPE-307-002',
      direction: 0,
      estimate: 420,
      nextBusTime: '2026-06-18T08:19:00+08:00',
      stopStatus: 0,
      srcUpdateTime: '2026-06-18T08:12:00+08:00',
    ),
  ],
);

/// Mock MRT live arrival shaped like the generated backend payload.
final mockMrtLive = Mrt_live(
  lineID: 'R',
  stationID: 'R10',
  system: 'TRTC',
  tripHeadSign: '淡水',
  destinationStaionID: 'R28',
  destinationStationName: '淡水',
  serviceStatus: 0,
  estimateTime: 210,
);

/// Mock TRA timetables shaped like the generated backend payload.
final mockTraTimetables = tra_timetables(
  items: [
    tra_timetable(
      trainDate: '2026-06-18',
      trainNo: '112',
      direction: 0,
      startingStationName: '高雄',
      endingStationName: '七堵',
      trainTypeID: '1',
      trainTypeCode: '1100',
      trainTypeName: '自強',
      tripLine: 0,
      mask: 0,
      note: '',
      startingTime: '2026-06-18T08:00:00+08:00',
      endingTime: '2026-06-18T12:10:00+08:00',
      travelTime: '4h10m',
    ),
  ],
);

/// Mock TRA stop times shaped like the generated backend payload.
final mockTraStoptimes = tra_stoptimes(
  items: [
    tra_stoptime(
      stationId: '1000',
      stationName: '高雄',
      stopSequence: 1,
      arrivalTime: '08:00',
      departureTime: '08:03',
      suspendedFlag: false,
    ),
    tra_stoptime(
      stationId: '1008',
      stationName: '台南',
      stopSequence: 2,
      arrivalTime: '08:35',
      departureTime: '08:37',
      suspendedFlag: false,
    ),
  ],
);

/// Mock THSR timetables shaped like the generated backend payload.
final mockThsrTimetables = thsr_timetables(
  items: [
    thsa_timetable(
      trainDate: '2026-06-18',
      trainNo: '0803',
      direction: 0,
      startingStationID: '0990',
      startingStationName: '南港',
      endingStationID: '1070',
      endingStationName: '左營',
      note: '',
      overnight: false,
      startingTime: '2026-06-18T08:00:00+08:00',
      endingTime: '2026-06-18T09:45:00+08:00',
      travelTime: '1h45m',
    ),
  ],
);

/// Mock THSR stop times shaped like the generated backend payload.
final mockThsrStoptimes = thsr_stoptimes(
  items: [
    thsa_stoptime(
      stationId: '0990',
      stationName: '南港',
      stopSequence: 1,
      arrivalTime: '08:00',
      departureTime: '08:00',
    ),
    thsa_stoptime(
      stationId: '1000',
      stationName: '台北',
      stopSequence: 2,
      arrivalTime: '08:08',
      departureTime: '08:10',
    ),
  ],
);
