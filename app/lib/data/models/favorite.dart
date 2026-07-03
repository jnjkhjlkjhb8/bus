import 'package:equatable/equatable.dart';

enum FavoriteType {
  busStop,
  busRoute,
  metroStation,
  railStation,
  railTrain,
  bikeStation,
}

class Favorite extends Equatable {
  const Favorite({
    required this.type,
    required this.refId,
    required this.title,
    this.subtitle = '',
    this.pinned = false,
    this.order = 0,
    this.createdAt = 0,
  });

  factory Favorite.fromMap(Map<dynamic, dynamic> map) => Favorite(
    type: FavoriteType.values.byName(map['type'] as String),
    refId: map['refId'] as String,
    title: map['title'] as String,
    subtitle: (map['subtitle'] as String?) ?? '',
    pinned: (map['pinned'] as bool?) ?? false,
    order: (map['order'] as int?) ?? 0,
    createdAt: (map['createdAt'] as int?) ?? 0,
  );

  final FavoriteType type;
  final String refId;
  final String title;
  final String subtitle;
  final bool pinned;
  final int order;
  final int createdAt;

  String get id => '${type.name}:$refId';

  Favorite copyWith({
    String? title,
    String? subtitle,
    bool? pinned,
    int? order,
    int? createdAt,
  }) => Favorite(
    type: type,
    refId: refId,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    pinned: pinned ?? this.pinned,
    order: order ?? this.order,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'refId': refId,
    'title': title,
    'subtitle': subtitle,
    'pinned': pinned,
    'order': order,
    'createdAt': createdAt,
  };

  @override
  List<Object?> get props => [
    type,
    refId,
    title,
    subtitle,
    pinned,
    order,
    createdAt,
  ];
}
