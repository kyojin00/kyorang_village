import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../friend/screens/chats_tab.dart';
import '../profile/screens/my_tab.dart';
import '../village/screens/explore_tab.dart';
import '../village/screens/my_villages_tab.dart';

/// 현재 선택된 하단 탭 인덱스 (Riverpod 3.x Notifier 패턴)
class HomeTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final homeTabIndexProvider = NotifierProvider<HomeTabIndex, int>(
  HomeTabIndex.new,
);

/// 교랑빌리지 메인 골격 (하단 탭 4개)
/// 0: 내 마을 / 1: 탐색 / 2: 채팅 / 3: 마이
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(homeTabIndexProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: IndexedStack(
        index: tabIndex,
        children: const [
          MyVillagesTab(),
          ExploreTab(),
          ChatsTab(),
          MyTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          border: Border(
            top: BorderSide(color: AppTheme.divider, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: tabIndex,
          onTap: (index) =>
              ref.read(homeTabIndexProvider.notifier).set(index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: '내 마을',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore_rounded),
              label: '탐색',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: '채팅',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: '마이',
            ),
          ],
        ),
      ),
    );
  }
}