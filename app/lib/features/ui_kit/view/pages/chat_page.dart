import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_chat_bubble.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Chat'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Message Bubbles',
            child: Column(
              children: [
                AppChatBubble(
                  text: '307 幾分鐘到？',
                  isSent: true,
                  time: '14:30',
                  isLastInGroup: false,
                ),
                AppChatBubble(
                  text: '還要再等一班',
                  isSent: true,
                  time: '14:30',
                ),
                AppChatBubble(
                  text: '系統顯示約 5 分鐘',
                  isSent: false,
                  time: '14:31',
                  isLastInGroup: false,
                ),
                AppChatBubble(
                  text: '目前在中正路口',
                  isSent: false,
                  time: '14:31',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
