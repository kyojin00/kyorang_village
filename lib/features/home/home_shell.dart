import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/unread_service.dart';
import '../../core/theme/app_theme.dart';
import '../friend/screens/chats_tab.dart';
import '../friend/services/friend_service.dart';
import '../profile/screens/my_tab.dart';
import '../village/screens/explore_tab.dart';
import '../village/screens/my_villages_tab.dart';

class HomeTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final homeTabIndexProvider = NotifierProvider<HomeTabIndex, int>(
  HomeTabIndex.new,
);

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(homeTabIndexProvider);
    final unread = ref.watch(unreadCountsProvider);
    final friendRequestCount =
        ref.watch(receivedRequestCountProvider).value ?? 0;

    final chatBadge = unread.dmTotal + friendRequestCount;
    final villageBadge = unread.villageTotal;

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
          items: [
            BottomNavigationBarItem(
              icon: _badge(_tabImage('home_outline'), villageBadge),
              activeIcon: _badge(_tabImage('home_filled'), villageBadge),
              label: '내 마을',
            ),
            BottomNavigationBarItem(
              icon: _tabImage('explore_outline'),
              activeIcon: _tabImage('explore_filled'),
              label: '탐색',
            ),
            BottomNavigationBarItem(
              icon: _badge(_tabImage('chat_outline'), chatBadge),
              activeIcon: _badge(_tabImage('chat_filled'), chatBadge),
              label: '채팅',
            ),
            BottomNavigationBarItem(
              icon: _tabImage('person_outline'),
              activeIcon: _tabImage('person_filled'),
              label: '마이',
            ),
          ],
        ),
      ),
    );
  }

  /// 탭바 PNG 아이콘 위젯
  Widget _tabImage(String name) {
    return Image.asset(
      'assets/icons/tabs/$name.png',
      width: 26,
      height: 26,
      filterQuality: FilterQuality.medium,
    );
  }

  Widget _badge(Widget icon, int count) {
    if (count <= 0) return icon;

    final label = count > 99 ? '99+' : '$count';

    return SizedBox(
      width: 32,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: Center(child: icon)),
          Positioned(
            right: 0,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.bgCard, width: 1.5),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}