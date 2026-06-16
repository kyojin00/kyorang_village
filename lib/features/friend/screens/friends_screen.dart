import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/friend.dart';
import '../services/dm_service.dart';
import '../services/friend_service.dart';
import '../widgets/profile_sheet.dart';
import 'dm_chat_screen.dart';

/// 친구 관리 화면 (친구 / 받은 신청 / 보낸 신청)
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  int _segment = 0; // 0: 친구, 1: 받은 신청, 2: 보낸 신청

  List<Friendship> _friends = [];
  List<Friendship> _received = [];
  List<Friendship> _sent = [];
  bool _loading = true;

  /// 처리 중인 friendship id (버튼 연타 방지)
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(friendServiceProvider);
      final results = await Future.wait([
        service.fetchFriends(),
        service.fetchReceivedRequests(),
        service.fetchSentRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0];
        _received = results[1];
        _sent = results[2];
        _loading = false;
      });
      ref.read(receivedRequestCountProvider.notifier).refresh();
    } catch (e) {
      print('[FRIENDS] 조회 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _accept(Friendship f) async {
    if (_processing.contains(f.id)) return;
    setState(() => _processing.add(f.id));

    try {
      await ref.read(friendServiceProvider).acceptRequest(f.id);
      if (!mounted) return;
      _snack('${f.otherNickname}님과 친구가 됐어요!');
      await _fetch();
    } catch (e) {
      print('[FRIENDS] 수락 실패: $e');
      if (!mounted) return;
      _snack('수락하지 못했어요.');
    } finally {
      _processing.remove(f.id);
    }
  }

  Future<void> _remove(Friendship f, String doneMessage) async {
    if (_processing.contains(f.id)) return;
    setState(() => _processing.add(f.id));

    try {
      await ref.read(friendServiceProvider).removeFriendship(f.id);
      if (!mounted) return;
      _snack(doneMessage);
      await _fetch();
    } catch (e) {
      print('[FRIENDS] 삭제 실패: $e');
      if (!mounted) return;
      _snack('처리하지 못했어요.');
    } finally {
      _processing.remove(f.id);
    }
  }

  Future<void> _openDm(Friendship f) async {
    try {
      final room =
          await ref.read(dmServiceProvider).openRoomWith(f.otherUserId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DmChatScreen(room: room)),
      );
    } catch (e) {
      print('[FRIENDS] DM 열기 실패: $e');
      if (!mounted) return;
      _snack('대화방을 열지 못했어요.');
    }
  }

  Future<void> _openProfile(Friendship f) async {
    await ProfileSheet.show(
      context,
      userId: f.otherUserId,
      nickname: f.otherNickname,
      avatarUrl: f.otherAvatarUrl,
    );
    _fetch(); // 시트에서 관계가 바뀌었을 수 있음
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final list = switch (_segment) {
      0 => _friends,
      1 => _received,
      _ => _sent,
    };

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: const Text('친구')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _segmentChip('친구 ${_friends.length}', 0),
                  const SizedBox(width: 8),
                  _segmentChip('받은 신청 ${_received.length}', 1),
                  const SizedBox(width: 8),
                  _segmentChip('보낸 신청 ${_sent.length}', 2),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? _emptyView()
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: AppTheme.primary,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: list.length,
                            itemBuilder: (context, i) => _row(list[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentChip(String label, int value) {
    final selected = _segment == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _segment = value),
      labelStyle: AppTheme.body(
        size: 13,
        color: selected ? AppTheme.textOnPrimary : AppTheme.textSub,
        weight: selected ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }

  Widget _row(Friendship f) {
    final processing = _processing.contains(f.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        onTap: () => _openProfile(f),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.bgSoft,
              backgroundImage: f.otherAvatarUrl != null
                  ? CachedNetworkImageProvider(f.otherAvatarUrl!)
                  : null,
              child: f.otherAvatarUrl == null
                  ? Text(
                      f.otherNickname.characters.first,
                      style: AppTheme.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                f.otherNickname,
                style: AppTheme.body(size: 15, weight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (processing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              ..._trailing(f),
          ],
        ),
      ),
    );
  }

  List<Widget> _trailing(Friendship f) {
    switch (_segment) {
      case 0: // 친구 → DM 바로가기
        return [
          IconButton(
            onPressed: () => _openDm(f),
            icon: const Icon(Icons.chat_bubble_outline_rounded,
                size: 20, color: AppTheme.primary),
          ),
        ];
      case 1: // 받은 신청 → 거절 / 수락
        return [
          TextButton(
            onPressed: () => _remove(f, '신청을 거절했어요.'),
            child: Text('거절',
                style: AppTheme.body(size: 13, color: AppTheme.textSub)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _accept(f),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: Text(
                '수락',
                style: AppTheme.body(
                  size: 12,
                  color: AppTheme.textOnPrimary,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ];
      default: // 보낸 신청 → 취소
        return [
          TextButton(
            onPressed: () => _remove(f, '신청을 취소했어요.'),
            child: Text('취소',
                style: AppTheme.body(size: 13, color: AppTheme.textSub)),
          ),
        ];
    }
  }

  Widget _emptyView() {
    final message = switch (_segment) {
      0 => '아직 친구가 없어요\n마을에서 만난 이웃에게 친구 신청을 보내 보세요!',
      1 => '받은 친구 신청이 없어요',
      _ => '보낸 친구 신청이 없어요',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTheme.body(
            size: 14,
            color: AppTheme.textSub,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}