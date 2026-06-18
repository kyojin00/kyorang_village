import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/account_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/safety_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/login_screen.dart';
import '../../friend/screens/blocked_users_screen.dart';
import 'account_security_screen.dart';
import 'my_profile_screen.dart';
import 'notification_settings_screen.dart';

class MyTab extends ConsumerStatefulWidget {
  const MyTab({super.key});

  @override
  ConsumerState<MyTab> createState() => _MyTabState();
}

class _MyTabState extends ConsumerState<MyTab> {
  String _nickname = '';
  String? _statusMessage;
  String? _avatarUrl;
  bool _loading = true;
  bool _busy = false;

  String get _myId => AuthService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('nickname, status_message, avatar_url')
          .eq('id', _myId)
          .single();

      if (!mounted) return;
      setState(() {
        _nickname = row['nickname'] as String? ?? '';
        _statusMessage = row['status_message'] as String?;
        _avatarUrl = row['avatar_url'] as String?;
        _loading = false;
      });
    } catch (e) {
      print('[MY_TAB] 프로필 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openMyProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyProfileScreen()),
    );
    _load();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('로그아웃',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text('로그아웃할까요?',
            style: AppTheme.body(size: 14, color: AppTheme.textSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: AppTheme.body(size: 14, color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('로그아웃',
                style: AppTheme.body(
                    size: 14,
                    color: AppTheme.error,
                    weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await NotificationService.instance.clearToken();
      await AuthService.instance.signOut();
      SafetyService.instance.clearCache();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print('[MY_TAB] 로그아웃 실패: $e');
      if (!mounted) return;
      _snack('로그아웃하지 못했어요.');
    }
  }

  Future<void> _deleteAccount() async {
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('회원 탈퇴',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '탈퇴하면 다음 정보가 영구적으로 삭제되며 되돌릴 수 없어요.\n\n'
          '· 프로필과 가입한 마을 정보\n'
          '· 채팅, 게시글, 댓글, 좋아요\n'
          '· 챌린지 참여 및 인증 기록\n'
          '· 친구와 1:1 대화 내용\n\n'
          '정말 탈퇴하시겠어요?',
          style:
              AppTheme.body(size: 14, color: AppTheme.textSub, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: AppTheme.body(size: 14, color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('탈퇴하기',
                style: AppTheme.body(
                    size: 14,
                    color: AppTheme.error,
                    weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (firstOk != true || !mounted) return;

    final finalOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('마지막 확인',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '$_nickname 님의 계정을 정말 삭제할까요?\n복구는 불가능해요.',
          style:
              AppTheme.body(size: 14, color: AppTheme.textSub, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: AppTheme.body(size: 14, color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('영구 삭제',
                style: AppTheme.body(
                    size: 14,
                    color: AppTheme.error,
                    weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (finalOk != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await NotificationService.instance.clearToken();
      await ref.read(accountServiceProvider).deleteAccount();
      SafetyService.instance.clearCache();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print('[MY_TAB] 탈퇴 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('탈퇴 처리에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text('마이', style: AppTheme.display(size: 28)),
                  const SizedBox(height: 16),

                  // ---- 프로필 카드 (탭하면 풀스크린 진입) ----
                  Card(
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusL),
                      onTap: _busy ? null : _openMyProfile,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: AppTheme.bgSoft,
                              backgroundImage: _avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      _avatarUrl!)
                                  : null,
                              child: _avatarUrl == null
                                  ? Text(
                                      _nickname.isEmpty
                                          ? '?'
                                          : _nickname.characters.first,
                                      style: AppTheme.body(
                                        size: 22,
                                        weight: FontWeight.w700,
                                        color: AppTheme.primary,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _nickname,
                                    style: AppTheme.body(
                                        size: 17,
                                        weight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (_statusMessage != null &&
                                            _statusMessage!.isNotEmpty)
                                        ? _statusMessage!
                                        : '프로필을 꾸며 보세요',
                                    style: AppTheme.body(
                                      size: 12,
                                      color: (_statusMessage != null &&
                                              _statusMessage!.isNotEmpty)
                                          ? AppTheme.textSub
                                          : AppTheme.textLight,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppTheme.textLight),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- 설정 ----
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.shield_outlined,
                              color: AppTheme.textMain, size: 22),
                          title: Text('계정 · 보안',
                              style: AppTheme.body(size: 14)),
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textLight),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const AccountSecurityScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                              Icons.notifications_none_rounded,
                              color: AppTheme.textMain,
                              size: 22),
                          title: Text('알림',
                              style: AppTheme.body(size: 14)),
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textLight),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const NotificationSettingsScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.block_rounded,
                              color: AppTheme.textMain, size: 22),
                          title: Text('차단한 이웃',
                              style: AppTheme.body(size: 14)),
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textLight),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const BlockedUsersScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.logout_rounded,
                              color: AppTheme.error, size: 22),
                          title: Text(
                            '로그아웃',
                            style: AppTheme.body(
                                size: 14,
                                color: AppTheme.error,
                                weight: FontWeight.w600),
                          ),
                          onTap: _logout,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                              Icons.person_remove_outlined,
                              color: AppTheme.textLight,
                              size: 22),
                          title: Text(
                            '회원 탈퇴',
                            style: AppTheme.body(
                                size: 14, color: AppTheme.textLight),
                          ),
                          onTap: _busy ? null : _deleteAccount,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}