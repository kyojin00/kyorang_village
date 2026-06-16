import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

/// 알림 설정 화면 — 종류별 ON/OFF
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _loading = true;
  bool _saving = false;

  bool _dm = true;
  bool _friendRequest = true;
  bool _mention = true;
  bool _postComment = true;
  bool _commentReply = true;
  bool _villageChat = false;

  String get _myId => AuthService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('notification_settings')
          .select()
          .eq('user_id', _myId)
          .maybeSingle();

      if (!mounted) return;
      if (row != null) {
        setState(() {
          _dm = row['dm_enabled'] as bool? ?? true;
          _friendRequest = row['friend_request_enabled'] as bool? ?? true;
          _mention = row['mention_enabled'] as bool? ?? true;
          _postComment = row['post_comment_enabled'] as bool? ?? true;
          _commentReply = row['comment_reply_enabled'] as bool? ?? true;
          _villageChat = row['village_chat_enabled'] as bool? ?? false;
          _loading = false;
        });
      } else {
        // 행이 없으면 기본값으로 새로 만들기
        await Supabase.instance.client
            .from('notification_settings')
            .insert({'user_id': _myId});
        if (!mounted) return;
        setState(() => _loading = false);
      }
    } catch (e) {
      print('[NOTI_SETTINGS] 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _update(String column, bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('notification_settings')
          .update({column: value}).eq('user_id', _myId);
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (e) {
      print('[NOTI_SETTINGS] 저장 실패: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('저장하지 못했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: const Text('알림 설정')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    '받고 싶은 알림 종류를 선택해 주세요',
                    style:
                        AppTheme.body(size: 13, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        _toggle(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: '1:1 대화 (DM)',
                          subtitle: '친구에게서 메시지가 오면 알려요',
                          value: _dm,
                          onChanged: (v) {
                            setState(() => _dm = v);
                            _update('dm_enabled', v);
                          },
                        ),
                        const Divider(height: 1),
                        _toggle(
                          icon: Icons.person_add_alt_1_rounded,
                          title: '친구 요청·수락',
                          subtitle: '누군가 친구를 신청하거나 수락하면 알려요',
                          value: _friendRequest,
                          onChanged: (v) {
                            setState(() => _friendRequest = v);
                            _update('friend_request_enabled', v);
                          },
                        ),
                        const Divider(height: 1),
                        _toggle(
                          icon: Icons.alternate_email_rounded,
                          title: '나를 멘션한 메시지',
                          subtitle: '마을 채팅에서 누군가 @로 언급할 때',
                          value: _mention,
                          onChanged: (v) {
                            setState(() => _mention = v);
                            _update('mention_enabled', v);
                          },
                        ),
                        const Divider(height: 1),
                        _toggle(
                          icon: Icons.comment_outlined,
                          title: '내 게시글에 댓글',
                          subtitle: '내가 쓴 게시글에 댓글이 달리면 알려요',
                          value: _postComment,
                          onChanged: (v) {
                            setState(() => _postComment = v);
                            _update('post_comment_enabled', v);
                          },
                        ),
                        const Divider(height: 1),
                        _toggle(
                          icon: Icons.reply_rounded,
                          title: '내 댓글에 답글',
                          subtitle: '내 댓글에 누군가 답글을 달면 알려요',
                          value: _commentReply,
                          onChanged: (v) {
                            setState(() => _commentReply = v);
                            _update('comment_reply_enabled', v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '마을 채팅',
                    style:
                        AppTheme.body(size: 13, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: _toggle(
                      icon: Icons.forum_outlined,
                      title: '마을 채팅 전체 알림',
                      subtitle: '활발한 마을이면 알림이 많을 수 있어요',
                      value: _villageChat,
                      onChanged: (v) {
                        setState(() => _villageChat = v);
                        _update('village_chat_enabled', v);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '시스템 알림 권한(폰 설정)이 꺼져 있으면 위 설정과 무관하게 알림이 오지 않아요.',
                    style: AppTheme.body(
                        size: 11,
                        color: AppTheme.textLight,
                        height: 1.6),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _toggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppTheme.textMain, size: 22),
      title: Text(title,
          style:
              AppTheme.body(size: 14, weight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style:
              AppTheme.body(size: 12, color: AppTheme.textLight)),
      value: value,
      onChanged: _saving ? null : onChanged,
      activeColor: AppTheme.primary,
    );
  }
}