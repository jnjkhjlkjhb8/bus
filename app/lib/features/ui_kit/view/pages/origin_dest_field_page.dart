import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/origin_dest_field.dart';
import 'package:wheres_the_car/shared/widgets/station_picker_sheet.dart';

class OriginDestFieldPage extends StatefulWidget {
  const OriginDestFieldPage({super.key});
  @override
  State<OriginDestFieldPage> createState() => _OriginDestFieldPageState();
}

class _OriginDestFieldPageState extends State<OriginDestFieldPage> {
  static const _stations = ['台北', '板橋', '桃園', '新竹', '台中', '台南', '高雄'];
  String _origin = '台北';
  String _dest = '高雄';

  Future<void> _pick(bool origin) async {
    final picked = await StationPickerSheet.show(context, _stations);
    if (picked == null || !mounted) return;
    setState(() => origin ? _origin = picked : _dest = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Origin → Dest Field'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Connected O→D with swap',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OriginDestField(
                origin: _origin,
                destination: _dest,
                onOriginTap: () => _pick(true),
                onDestTap: () => _pick(false),
                onSwap: () => setState(() {
                  final t = _origin;
                  _origin = _dest;
                  _dest = t;
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
