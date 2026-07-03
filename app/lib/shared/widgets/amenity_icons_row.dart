import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TrainAmenities {
  const TrainAmenities({
    this.bike = false,
    this.overnight = false,
    this.daily = false,
    this.businessClass = false,
    this.freeSeating = false,
    this.bento = false,
    this.nursing = false,
    this.children = false,
    this.table = false,
    this.wheelchair = false,
  });

  final bool bike;
  final bool overnight;
  final bool daily;
  final bool businessClass;
  final bool freeSeating;
  final bool bento;
  final bool nursing;
  final bool children;
  final bool table;
  final bool wheelchair;
}

class AmenityIconsRow extends StatelessWidget {
  const AmenityIconsRow({required this.amenities, super.key});
  final TrainAmenities amenities;

  static const _all = [
    ('bike', 'assets/amenities/bike.svg'),
    ('overnight', 'assets/amenities/overnight.svg'),
    ('daily', 'assets/amenities/daily.svg'),
    ('business', 'assets/amenities/business.svg'),
    ('freeSeating', 'assets/amenities/free_seat.svg'),
    ('bento', 'assets/amenities/bento.svg'),
    ('nursing', 'assets/amenities/nursing.svg'),
    ('children', 'assets/amenities/children.svg'),
    ('table', 'assets/amenities/table.svg'),
    ('wheelchair', 'assets/amenities/wheelchair.svg'),
  ];

  bool _enabled(String key) {
    switch (key) {
      case 'bike':
        return amenities.bike;
      case 'overnight':
        return amenities.overnight;
      case 'daily':
        return amenities.daily;
      case 'business':
        return amenities.businessClass;
      case 'freeSeating':
        return amenities.freeSeating;
      case 'bento':
        return amenities.bento;
      case 'nursing':
        return amenities.nursing;
      case 'children':
        return amenities.children;
      case 'table':
        return amenities.table;
      case 'wheelchair':
        return amenities.wheelchair;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _all.where((e) => _enabled(e.$1)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: visible
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SvgPicture.asset(e.$2, width: 24, height: 24),
            ),
          )
          .toList(),
    );
  }
}
