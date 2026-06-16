import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/friend.dart';
import '../services/dm_service.dart';
import '../services/friend_service.dart';
import 'dm_chat_screen.dart';
import 'friends_screen.dart';

/// 채팅 탭 - 1:1 DM 목록 + 친구 관리 진입
class ChatsTab extends ConsumerStatefulWidget {
  const ChatsTab({super.key});

  @override
  ConsumerState<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<ChatsTab> {
  List<DmRoom> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final rooms = await ref.read(dmServiceProvider).fetchRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      print('[CHATS_TAB] 목록 조회 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openRoom(DmRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DmChatScreen(room: room)),
    );
    _fetch(); // 마지막 메시지 갱신
  }

  Future<void> _openFriends() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
    _fetch();
    ref.read(receivedRequestCountProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final requestCount =
        ref.watch(receivedRequestCountProvider).value ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Text('채팅', style: AppTheme.display(size: 28)),
                  const Spacer(),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        onPressed: _openFriends,
                        icon: const Icon(Icons.people_alt_rounded,
                            color: AppTheme.textMain),
                      ),
                      if (requestCount > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.error,
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFull),
                            ),
                            constraints:
                                const BoxConstraints(minWidth: 16),
                            child: Text(
                              requestCount > 9 ? '9+' : '$requestCount',
                              textAlign: TextAlign.center,
                              style: AppTheme.body(
                                size: 10,
                                color: AppTheme.textOnPrimary,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rooms.isEmpty
                      ? _emptyView()
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: AppTheme.primary,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: _rooms.length,
                            itemBuilder: (context, i) =>
                                _roomRow(_rooms[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roomRow(DmRoom room) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      onTap: () => _openRoom(room),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.bgSoft,
              backgroundImage: room.otherAvatarUrl != null
                  ? CachedNetworkImageProvider(room.otherAvatarUrl!)
                  : null,
              child: room.otherAvatarUrl == null
                  ? Text(
                      room.otherNickname.characters.first,
                      style: AppTheme.body(
                        size: 17,
                        weight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.otherNickname,
                    style:
                        AppTheme.body(size: 15, weight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    room.lastMessage ?? '대화를 시작해 보세요',
                    style:
                        AppTheme.body(size: 13, color: AppTheme.textSub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              room.lastMessageTimeLabel,
              style: AppTheme.body(size: 11, color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💬', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              '아직 대화가 없어요\n친구를 맺고 첫 메시지를 보내 보세요!',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 14,
                color: AppTheme.textSub,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 160,
              child: ElevatedButton(
                onPressed: _openFriends,
                child: const Text('친구 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}