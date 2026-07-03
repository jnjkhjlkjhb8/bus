import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_input.dart';

class InputPage extends StatelessWidget {
  const InputPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: DetailAppBar(title: 'Input'),
      body: _InputBody(),
    );
  }
}

class _InputBody extends StatelessWidget {
  const _InputBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: const [
        ShowcaseSection(
          title: 'Default',
          child: AppInput(label: '站名', hint: '輸入站名'),
        ),
        ShowcaseSection(
          title: 'With Helper',
          child: AppInput(
            label: '電話',
            hint: '09XX-XXX-XXX',
            helper: '請輸入台灣手機號碼',
          ),
        ),
        ShowcaseSection(
          title: 'Error State',
          child: AppInput(
            label: '電話',
            hint: '09XX-XXX-XXX',
            error: '格式不正確',
          ),
        ),
        ShowcaseSection(
          title: 'With Prefix Icon',
          child: AppInput(
            label: '搜尋',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
        ),
        ShowcaseSection(
          title: 'Password',
          child: AppInput(label: '密碼', obscureText: true),
        ),
      ],
    );
  }
}
