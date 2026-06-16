import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/account_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/safety_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/login_screen.dart';
import '../../friend/screens/blocked_users_screen.dart';
import 'account_security_screen.dart';
import 'notification_settings_screen.dart';

/// 마이 탭 - 내 프로필 + 설정
class MyTab extends ConsumerStatefulWidget {
  const MyTab({super.key});

  @override
  ConsumerState<MyTab> createState() => _MyTabState();
}

class _MyTabState extends ConsumerState<MyTab> {
  String _nickname = '';
  String? _bio;
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
          .select('nickname, bio, avatar_url')
          .eq('id', _myId)
          .single();

      if (!mounted) return;
      setState(() {
        _nickname = row['nickname'] as String? ?? '';
        _bio = row['bio'] as String?;
        _avatarUrl = row['avatar_url'] as String?;
        _loading = false;
      });
    } catch (e) {
      print('[MY_TAB] 프로필 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _changeAvatar() async {
    if (_busy) return;

    final picked = await ref.read(storageServiceProvider).pickImage();
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final oldUrl = _avatarUrl;

    try {
      final url = await ref.read(storageServiceProvider).uploadImage(
            bucket: StorageBuckets.avatars,
            file: picked,
          );

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': url}).eq('id', _myId);

      // 이전 아바타 정리
      if (oldUrl != null) {
        await StorageService.instance.deleteByUrl(
          bucket: StorageBuckets.avatars,
          url: oldUrl,
        );
      }

      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _busy = false;
      });
      _snack('프로필 사진을 바꿨어요.');
    } catch (e) {
      print('[MY_TAB] 아바타 변경 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('사진을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _openEditSheet() async {
    final result = await showModalBottomSheet<_ProfileEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (_) => _EditSheet(nickname: _nickname, bio: _bio),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'nickname': result.nickname,
        'bio': result.bio,
      }).eq('id', _myId);

      if (!mounted) return;
      setState(() {
        _nickname = result.nickname;
        _bio = result.bio;
        _busy = false;
      });
      _snack('프로필을 수정했어요.');
    } catch (e) {
      print('[MY_TAB] 프로필 수정 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('수정하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
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
        content: Text(
          '로그아웃할까요?',
          style: AppTheme.body(size: 14, color: AppTheme.textSub),
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
              '로그아웃',
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

    try {
      // FCM 토큰 정리 - 다음 사용자에게 잘못 가지 않도록
      await NotificationService.instance.clearToken();
      await AuthService.instance.signOut();
      SafetyService.instance.clearCache(); // 차단 캐시 초기화
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

  // ===========================================================
  // 회원 탈퇴
  // ===========================================================

  Future<void> _deleteAccount() async {
    // 1단계: 안내 + 1차 확인
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
            child: Text(
              '탈퇴하기',
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
    if (firstOk != true || !mounted) return;

    // 2단계: 최종 확인
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
            child: Text(
              '영구 삭제',
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
    if (finalOk != true || !mounted) return;

    // 진행
    setState(() => _busy = true);
    try {
      // FCM 토큰 정리 (계정 삭제 전에 — 삭제 후엔 호출 불가)
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

  // ===========================================================
  // UI
  // ===========================================================

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

                  // ---- 프로필 카드 ----
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 40,
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
                                          size: 28,
                                          weight: FontWeight.w700,
                                          color: AppTheme.primary,
                                        ),
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onTap: _busy ? null : _changeAvatar,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: AppTheme.bgCard,
                                          width: 2),
                                    ),
                                    child: _busy
                                        ? const Padding(
                                            padding: EdgeInsets.all(6),
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color:
                                                  AppTheme.textOnPrimary,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.camera_alt_rounded,
                                            size: 14,
                                            color: AppTheme.textOnPrimary,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(_nickname,
                              style: AppTheme.display(size: 24)),
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
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _busy ? null : _openEditSheet,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: const BorderSide(
                                    color: AppTheme.divider),
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.radiusM),
                                ),
                              ),
                              child: const Text('프로필 수정'),
                            ),
                          ),
                        ],
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
                          title: Text(
                            '계정 · 보안',
                            style: AppTheme.body(size: 14),
                          ),
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textLight),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AccountSecurityScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                              Icons.notifications_none_rounded,
                              color: AppTheme.textMain,
                              size: 22),
                          title: Text(
                            '알림',
                            style: AppTheme.body(size: 14),
                          ),
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textLight),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const NotificationSettingsScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.block_rounded,
                              color: AppTheme.textMain, size: 22),
                          title: Text(
                            '차단한 이웃',
                            style: AppTheme.body(size: 14),
                          ),
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textLight),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const BlockedUsersScreen(),
                              ),
                            );
                          },
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

// =============================================================
// 프로필 수정 바텀시트
// =============================================================

class _ProfileEdit {
  const _ProfileEdit({required this.nickname, this.bio});

  final String nickname;
  final String? bio;
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.nickname, this.bio});

  final String nickname;
  final String? bio;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.nickname);
    _bioController = TextEditingController(text: widget.bio ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  bool get _canSave => _nicknameController.text.trim().length >= 2;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('프로필 수정', style: AppTheme.display(size: 22)),
              const SizedBox(height: 14),
              TextField(
                controller: _nicknameController,
                maxLength: 12,
                style: AppTheme.body(size: 15, weight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '닉네임 (2~12자)',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bioController,
                maxLines: 2,
                maxLength: 60,
                style: AppTheme.body(size: 14),
                decoration: const InputDecoration(
                  hintText: '한 줄 소개 (선택)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _canSave
                    ? () => Navigator.of(context).pop(
                          _ProfileEdit(
                            nickname: _nicknameController.text.trim(),
                            bio: _bioController.text.trim().isEmpty
                                ? null
                                : _bioController.text.trim(),
                          ),
                        )
                    : null,
                child: const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}