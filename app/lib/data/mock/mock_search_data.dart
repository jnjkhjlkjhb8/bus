import 'package:wheres_the_car/data/models/search_models.dart';

const mockSearchResults = [
  // ── 公車路線 ──────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.busRoute,
    uid: 'TPE-307-main',
    name: '307',
    city: 'Taipei',
    depart: '板橋',
    destin: '撫遠街',
  ),
  BackendSearchResult(
    type: AppSearchResultType.busRoute,
    uid: 'TPE-1-main',
    name: '1',
    city: 'Taipei',
    depart: '東園',
    destin: '捷運劍潭站',
  ),

  BackendSearchResult(
    type: AppSearchResultType.traTrain,
    uid: 'TRA-112',
    name: '112 自強號',
    depart: '高雄',
    destin: '七堵',
  ),
  // ── 高鐵列車 ──────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.thsrTrain,
    uid: 'THSR-0803',
    name: '0803 高鐵',
    depart: '南港',
    destin: '左營',
  ),

  // ── 台鐵車站 ──────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.traStation,
    uid: 'TRA-1000',
    name: '台北',
    city: 'Taipei',
  ),

  // ── 高鐵車站 ──────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.thsrStation,
    uid: 'THSR-NanGang',
    name: '南港',
    city: 'Taipei',
  ),

  // ── 捷運車站 ──────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.mrtStation,
    uid: 'TRTC-R10',
    name: '中山',
    city: 'Taipei',
  ),

  // ── 公車站 ────────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.busStation,
    uid: 'TPE-BS-001',
    name: '台北車站',
    city: 'Taipei',
  ),

  // ── YouBike 站 ────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.bikeStation,
    uid: 'TPE-UBIKE-500101001',
    name: '捷運科技大樓站',
    city: 'Taipei',
  ),

  // ── 地點 ──────────────────────────────────────────────────
  BackendSearchResult(
    type: AppSearchResultType.place,
    uid: 'PLACE-001',
    name: '統領百貨',
    city: 'Taoyuan',
  ),
];
