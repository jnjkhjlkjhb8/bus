import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_stepper_widget.dart';

class StepperPage extends StatefulWidget {
  const StepperPage({super.key});

  @override
  State<StepperPage> createState() => _StepperPageState();
}

class _StepperPageState extends State<StepperPage> {
  var _step = 1;
  static const _steps = ['選擇起點', '選擇終點', '確認路線', '出發'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Stepper'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Horizontal',
            child: AppStepperWidget(
              steps: _steps,
              currentStep: _step,
              horizontal: true,
            ),
          ),
          ShowcaseSection(
            title: 'Vertical',
            child: AppStepperWidget(steps: _steps, currentStep: _step),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton.outlined(
                label: '上一步',
                onPressed: _step > 0 ? () => setState(() => _step--) : null,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: '下一步',
                onPressed: _step < _steps.length - 1
                    ? () => setState(() => _step++)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
