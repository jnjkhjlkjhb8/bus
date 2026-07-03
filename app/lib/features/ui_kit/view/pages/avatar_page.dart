import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_avatar.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class AvatarPage extends StatelessWidget {
  const AvatarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: DetailAppBar(title: 'Avatar'),
      body: _Body(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: const [
        ShowcaseSection(
          title: 'Sizes',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppAvatar(size: 24, initials: 'AB'),
              SizedBox(width: 12),
              AppAvatar(size: 32, initials: 'AB'),
              SizedBox(width: 12),
              AppAvatar(initials: 'AB'),
              SizedBox(width: 12),
              AppAvatar(size: 56, initials: 'AB'),
            ],
          ),
        ),
        ShowcaseSection(
          title: 'Icon Fallback',
          child: Row(
            children: [
              AppAvatar(),
              SizedBox(width: 12),
              AppAvatar(icon: Icons.directions_bus_rounded),
            ],
          ),
        ),
        ShowcaseSection(
          title: 'Status',
          child: Row(
            children: [
              AppAvatar(initials: 'JD', status: AvatarStatus.online),
              SizedBox(width: 12),
              AppAvatar(initials: 'JD', status: AvatarStatus.offline),
            ],
          ),
        ),
      ],
    );
  }
}
