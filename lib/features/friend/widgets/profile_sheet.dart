import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/safety_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/friend.dart';
import '../screens/dm_chat_screen.dart';
import '../services/dm_service.dart';
import '../services/friend_service.dart';

/// 공용 프로필 바텀시트
/// 마을 멤버 목록, 게시글, 채팅 등 어디서든 사람을 탭하면 띄운다.
/// 관계 상태에 따라 액션 버튼이 달라지고,
/// 하단에 신고하기 / 차단하기가 항상 제공된다 (본인 제외).
class ProfileSheet {
  ProfileSheet._();

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required String nickname,
    String? avatarUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (_) => _ProfileSheetBody(
        userId: userId,
        nickname: nickname,
        avatarUrl: avatarUrl,
      ),
    );
  }
}

class _ProfileSheetBody extends ConsumerStatefulWidget {
  const _ProfileSheetBody({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
  });

  final String userId;
  final String nickname;
  final String? avatarUrl;

  @override
  ConsumerState<_ProfileSheetBody> createState() =>
      _ProfileSheetBodyState();
}

class _ProfileSheetBodyState extends ConsumerState<_ProfileSheetBody> {
  String? _bio;
  Friendship? _relation;
  bool _blocked = false;
  bool _loading = true;
  bool _busy = false;

  String get _myId => AuthService.instance.currentUserId ?? '';
  bool get _isMe => widget.userId == _myId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profileRow = await Supabase.instance.client
          .from('profiles')
          .select('bio')
          .eq('id', widget.userId)
          .maybeSingle();

      Friendship? relation;
      bool blocked = false;
      if (!_isMe) {
        relation = await ref
            .read(friendServiceProvider)
            .getRelationWith(widget.userId);
        blocked =
            await ref.read(safetyServiceProvider).isBlocked(widget.userId);
      }

      if (!mounted) return;
      setState(() {
        _bio = profileRow?['bio'] as String?;
        _relation = relation;
        _blocked = blocked;
        _loading = false;
      });
    } catch (e) {
      print('[PROFILE_SHEET] 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ===========================================================
  // 친구 / DM 액션
  // ===========================================================

  Future<void> _sendRequest() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final result =
          await ref.read(friendServiceProvider).sendRequest(widget.userId);
      final relation =
          await ref.read(friendServiceProvider).getRelationWith(widget.userId);

      if (!mounted) return;
      setState(() {
        _relation = relation;
        _busy = false;
      });
      _snack(result.message);
    } catch (e) {
      print('[PROFILE_SHEET] 신청 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('친구 신청을 보내지 못했어요.');
    }
  }

  Future<void> _accept() async {
    final relation = _relation;
    if (relation == null || _busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(friendServiceProvider).acceptRequest(relation.id);
      ref.read(receivedRequestCountProvider.notifier).refresh();

      if (!mounted) return;
      final updated =
          await ref.read(friendServiceProvider).getRelationWith(widget.userId);
      if (!mounted) return;
      setState(() {
        _relation = updated;
        _busy = false;
      });
      _snack('${widget.nickname}님과 친구가 됐어요!');
    } catch (e) {
      print('[PROFILE_SHEET] 수락 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('수락하지 못했어요.');
    }
  }

  Future<void> _remove({required String doneMessage}) async {
    final relation = _relation;
    if (relation == null || _busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(friendServiceProvider).removeFriendship(relation.id);
      ref.read(receivedRequestCountProvider.notifier).refresh();

      if (!mounted) return;
      setState(() {
        _relation = null;
        _busy = false;
      });
      _snack(doneMessage);
    } catch (e) {
      print('[PROFILE_SHEET] 관계 삭제 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('처리하지 못했어요.');
    }
  }

  Future<void> _openDm() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final room =
          await ref.read(dmServiceProvider).openRoomWith(widget.userId);
      if (!mounted) return;
      Navigator.of(context).pop(); // 시트 닫기
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DmChatScreen(room: room)),
      );
    } catch (e) {
      print('[PROFILE_SHEET] DM 열기 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('대화방을 열지 못했어요.');
    }
  }

  // ===========================================================
  // 신고 / 차단
  // ===========================================================

  Future<void> _report() async {
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text(
          '${widget.nickname}님을 신고할까요?',
          style: AppTheme.body(size: 16, weight: FontWeight.w700),
        ),
        children: ReportReason.values
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(r),
                child: Text(r.label, style: AppTheme.body(size: 14)),
              ),
            )
            .toList(),
      ),
    );
    if (reason == null || !mounted) return;

    try {
      await ref.read(safetyServiceProvider).report(
            targetType: ReportTargetType.user,
            targetId: widget.userId,
            reason: reason,
          );
      if (!mounted) return;
      _snack('신고가 접수됐어요. 빠르게 확인할게요.');
    } catch (e) {
      print('[PROFILE_SHEET] 신고 실패: $e');
      if (!mounted) return;
      _snack('신고를 접수하지 못했어요.');
    }
  }

  Future<void> _toggleBlock() async {
    if (_busy) return;

    if (_blocked) {
      // 차단 해제
      setState(() => _busy = true);
      try {
        await ref.read(safetyServiceProvider).unblock(widget.userId);
        if (!mounted) return;
        setState(() {
          _blocked = false;
          _busy = false;
        });
        _snack('차단을 해제했어요.');
      } catch (e) {
        print('[PROFILE_SHEET] 차단 해제 실패: $e');
        if (!mounted) return;
        setState(() => _busy = false);
        _snack('처리하지 못했어요.');
      }
      return;
    }

    // 차단
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('차단하기',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '${widget.nickname}님을 차단할까요?\n'
          '이 사람의 채팅, 게시글, 댓글이 더 이상 보이지 않아요.',
          style:
              AppTheme.body(size: 14, color: AppTheme.textSub, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: AppTheme.body(size: 14, color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '차단',
              style: AppTheme.body(
                size: 14,
                color: AppTheme.error,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(safetyServiceProvider).block(widget.userId);
      // 차단하면 친구 관계도 정리
      final relation = _relation;
      if (relation != null) {
        await ref.read(friendServiceProvider).removeFriendship(relation.id);
      }

      if (!mounted) return;
      setState(() {
        _blocked = true;
        _relation = null;
        _busy = false;
      });
      _snack('${widget.nickname}님을 차단했어요.');
    } catch (e) {
      print('[PROFILE_SHEET] 차단 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('차단하지 못했어요.');
    }
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppTheme.bgSoft,
              backgroundImage: widget.avatarUrl != null
                  ? CachedNetworkImageProvider(widget.avatarUrl!)
                  : null,
              child: widget.avatarUrl == null
                  ? Text(
                      widget.nickname.characters.first,
                      style: AppTheme.body(
                        size: 26,
                        weight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(widget.nickname, style: AppTheme.display(size: 24)),
            if (_bio != null && _bio!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _bio!,
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  size: 13,
                  color: AppTheme.textSub,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else ...[
              _actionArea(),
              if (!_isMe) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _report,
                      child: Text(
                        '신고하기',
                        style: AppTheme.body(
                            size: 12, color: AppTheme.textLight),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 12,
                      color: AppTheme.divider,
                    ),
                    TextButton(
                      onPressed: _busy ? null : _toggleBlock,
                      child: Text(
                        _blocked ? '차단 해제' : '차단하기',
                        style: AppTheme.body(
                            size: 12, color: AppTheme.textLight),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionArea() {
    if (_isMe) {
      return Text(
        '나예요',
        style: AppTheme.body(size: 13, color: AppTheme.textLight),
      );
    }

    // 차단한 상대 → 친구/DM 액션 숨김
    if (_blocked) {
      return Text(
        '차단한 이웃이에요',
        style: AppTheme.body(size: 13, color: AppTheme.textLight),
      );
    }

    final relation = _relation;

    // 관계 없음 → 친구 신청
    if (relation == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _sendRequest,
          child: _busyChild(const Text('친구 신청')),
        ),
      );
    }

    // 친구 → DM / 끊기
    if (relation.isAccepted) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _openDm,
              child: _busyChild(const Text('메시지 보내기')),
            ),
          ),
          TextButton(
            onPressed:
                _busy ? null : () => _remove(doneMessage: '친구를 끊었어요.'),
            child: Text(
              '친구 끊기',
              style: AppTheme.body(size: 12, color: AppTheme.textLight),
            ),
          ),
        ],
      );
    }

    // 내가 신청한 상태 → 취소
    if (relation.sentByMe(_myId)) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed:
              _busy ? null : () => _remove(doneMessage: '신청을 취소했어요.'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSub,
            side: const BorderSide(color: AppTheme.divider),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
          ),
          child: _busyChild(const Text('친구 신청 취소')),
        ),
      );
    }

    // 상대가 신청한 상태 → 수락 / 거절
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed:
                _busy ? null : () => _remove(doneMessage: '신청을 거절했어요.'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSub,
              side: const BorderSide(color: AppTheme.divider),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
              ),
            ),
            child: const Text('거절'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _busy ? null : _accept,
            child: _busyChild(const Text('수락하기')),
          ),
        ),
      ],
    );
  }

  Widget _busyChild(Widget child) {
    if (!_busy) return child;
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
}