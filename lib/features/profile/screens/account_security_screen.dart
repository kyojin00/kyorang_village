import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

/// 계정·보안 화면
/// 이메일 / Google 연결 관리 + 비밀번호 재설정
class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  ConsumerState<AccountSecurityScreen> createState() =>
      _AccountSecurityScreenState();
}

class _AccountSecurityScreenState
    extends ConsumerState<AccountSecurityScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _busy = false;

  List<UserIdentity> _identities = [];
  bool _googleLinking = false;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.userUpdated) {
        if (_googleLinking) {
          await _refreshIdentities();
          if (!mounted) return;
          setState(() {
            _googleLinking = false;
            _busy = false;
          });
          _snack('Google 계정이 연결됐어요.');
        } else {
          await _refreshIdentities();
          if (!mounted) return;
          setState(() {});
        }
      }
    });

    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _googleLinking) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || !_googleLinking) return;
        setState(() {
          _googleLinking = false;
          _busy = false;
        });
        _showLinkFailedDialog();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshIdentities() async {
    try {
      final res = await Supabase.instance.client.auth.refreshSession();
      final user = res.user;
      if (user != null) {
        _identities = user.identities ?? [];
      }
    } catch (e) {
      print('[ACCOUNT] refreshSession 실패, getUser로 폴백: $e');
      try {
        final res = await Supabase.instance.client.auth.getUser();
        final user = res.user;
        if (user != null) {
          _identities = user.identities ?? [];
        }
      } catch (e2) {
        print('[ACCOUNT] getUser도 실패: $e2');
      }
    }
  }

  Future<void> _load() async {
    final uid = AuthService.instance.currentUserId;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    await _refreshIdentities();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _linkGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _googleLinking = true;
    });
    try {
      await AuthService.instance.linkGoogle();
    } catch (e) {
      print('[ACCOUNT] Google 연결 실패: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _googleLinking = false;
      });
      _showLinkFailedDialog();
    }
  }

  Future<void> _unlinkProvider(UserIdentity identity, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('$label 연결 해제',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '$label 연결을 해제할까요?\n'
          '해제 후엔 남은 로그인 방법으로만 들어올 수 있어요.',
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
            child: Text('해제',
                style: AppTheme.body(
                    size: 14,
                    color: AppTheme.error,
                    weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService.instance.unlinkIdentity(identity);
      await _refreshIdentities();
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('$label 연결을 해제했어요.');
    } catch (e) {
      print('[ACCOUNT] $label 해제 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('해제에 실패했어요. (마지막 로그인 방법은 해제할 수 없어요)');
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = AuthService.instance.currentEmail;
    if (email == null) {
      _snack('이메일 정보를 찾을 수 없어요.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('비밀번호 재설정',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '$email 주소로 비밀번호 재설정 메일을 보낼까요?',
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
            child: Text('보내기',
                style: AppTheme.body(
                    size: 14,
                    color: AppTheme.primary,
                    weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('재설정 메일을 보냈어요. 메일함을 확인해 주세요.');
    } catch (e) {
      print('[ACCOUNT] 비번 재설정 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('메일을 보내지 못했어요.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showLinkFailedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('연결하지 못했어요',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '이미 다른 계정에 연결된 Google이거나, 연결이 취소됐어요.\n'
          '다른 Google 계정으로 다시 시도해 주세요.',
          style:
              AppTheme.body(size: 14, color: AppTheme.textSub, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '확인',
              style: AppTheme.body(
                size: 14,
                color: AppTheme.primary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    UserIdentity? emailIdentity;
    UserIdentity? googleIdentity;
    for (final i in _identities) {
      if (i.provider == 'email') emailIdentity = i;
      if (i.provider == 'google') googleIdentity = i;
    }
    final email = AuthService.instance.currentEmail;
    final googleEmail = googleIdentity?.identityData?['email'] as String?;

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: const Text('계정 · 보안')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    '로그인 방법',
                    style: AppTheme.body(
                        size: 13, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 8),

                  // 이메일
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.email_outlined,
                          color: AppTheme.primary, size: 22),
                      title: Text('이메일',
                          style: AppTheme.body(
                              size: 14, weight: FontWeight.w600)),
                      subtitle: Text(
                        email ?? '연결되지 않음',
                        style: AppTheme.body(
                            size: 13, color: AppTheme.textSub),
                      ),
                      trailing: (emailIdentity != null && email != null)
                          ? TextButton(
                              onPressed: _busy ? null : _sendPasswordReset,
                              child: Text('비번 변경',
                                  style: AppTheme.body(
                                      size: 13,
                                      color: AppTheme.primary,
                                      weight: FontWeight.w700)),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Google
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_circle_rounded,
                          color: AppTheme.textMain, size: 22),
                      title: Text('Google',
                          style: AppTheme.body(
                              size: 14, weight: FontWeight.w600)),
                      subtitle: Text(
                        googleEmail ?? '연결되지 않음',
                        style: AppTheme.body(
                          size: 13,
                          color: googleEmail != null
                              ? AppTheme.textSub
                              : AppTheme.textLight,
                        ),
                      ),
                      trailing: _googleLinking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : (googleIdentity != null
                              ? TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _unlinkProvider(
                                          googleIdentity!, 'Google'),
                                  child: Text('해제',
                                      style: AppTheme.body(
                                          size: 13,
                                          color: AppTheme.textSub)),
                                )
                              : TextButton(
                                  onPressed: _busy ? null : _linkGoogle,
                                  child: Text('연결',
                                      style: AppTheme.body(
                                          size: 13,
                                          color: AppTheme.primary,
                                          weight: FontWeight.w700)),
                                )),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    '여러 로그인 방법을 연결해두면 한쪽을 잃어도 다른 쪽으로 들어올 수 있어요.\n'
                    '비밀번호를 바꾸려면 "비번 변경"을 눌러 메일로 받은 링크에서 새 비밀번호를 설정해 주세요.',
                    style: AppTheme.body(
                        size: 12,
                        color: AppTheme.textLight,
                        height: 1.6),
                  ),
                ],
              ),
      ),
    );
  }
}