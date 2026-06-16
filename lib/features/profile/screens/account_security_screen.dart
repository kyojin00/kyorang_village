import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import 'phone_change_screen.dart';

/// 계정·보안 화면
/// 마이 탭에서 진입. 전화번호 / Google / 이메일 연결 관리.
class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  ConsumerState<AccountSecurityScreen> createState() =>
      _AccountSecurityScreenState();
}

class _AccountSecurityScreenState
    extends ConsumerState<AccountSecurityScreen>
    with WidgetsBindingObserver {
  String? _phone;
  bool _loading = true;
  bool _busy = false;

  /// 화면이 직접 들고 있는 identity 리스트 (캐시 우회).
  /// AuthService.currentIdentities는 stale일 수 있어 사용하지 않는다.
  List<UserIdentity> _identities = [];

  /// Google 연결 시도 중. 콜백 결과 대기 상태.
  bool _googleLinking = false;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // onAuthStateChange: OAuth 콜백 후 SIGNED_IN 또는
    // userUpdated 이벤트가 발생하면 identity 목록이 갱신된 것.
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.userUpdated) {
        if (_googleLinking) {
          // Google 연결 성공으로 간주 - identity 다시 받기
          await _refreshIdentities();
          if (!mounted) return;
          setState(() {
            _googleLinking = false;
            _busy = false;
          });
          _snack('Google 계정이 연결됐어요.');
        } else {
          // 다른 이유의 갱신 → identity 갱신 후 UI 다시 그리기
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
    // 사용자가 브라우저에서 앱으로 돌아왔을 때 _googleLinking이 아직 true면
    // 연결이 실패한 것 (이미 다른 계정에 연결됐거나, 사용자가 취소).
    if (state == AppLifecycleState.resumed && _googleLinking) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || !_googleLinking) return;
        // 2초 안에 onAuthStateChange가 안 왔으면 실패로 간주
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
      // 서버에서 세션과 user 정보를 강제로 새로 받아온다.
      final res =
          await Supabase.instance.client.auth.refreshSession();
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

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('phone')
          .eq('id', uid)
          .single();
      if (!mounted) return;
      setState(() {
        _phone = row['phone'] as String?;
        _loading = false;
      });
    } catch (e) {
      print('[ACCOUNT] 조회 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _openPhoneChange() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PhoneChangeScreen(currentPhone: _phone ?? ''),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _linkGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _googleLinking = true;
    });
    try {
      await AuthService.instance.linkGoogle();
      // 결과는 onAuthStateChange 또는 didChangeAppLifecycleState에서 처리
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
          '$label 연결을 해제할까요?\n해제 후엔 휴대폰 인증으로만 로그인할 수 있어요.',
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
      _snack('해제에 실패했어요.');
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
    final googleIdentity = _identities
        .where((i) => i.provider == 'google')
        .cast<UserIdentity?>()
        .firstWhere((_) => true, orElse: () => null);
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

                  // 전화번호 (마스터)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.phone_iphone_rounded,
                          color: AppTheme.primary, size: 22),
                      title: Text('휴대폰',
                          style: AppTheme.body(
                              size: 14, weight: FontWeight.w600)),
                      subtitle: Text(_formatPhone(_phone ?? ''),
                          style: AppTheme.body(
                              size: 13, color: AppTheme.textSub)),
                      trailing: TextButton(
                        onPressed: _busy ? null : _openPhoneChange,
                        child: Text('변경',
                            style: AppTheme.body(
                                size: 13,
                                color: AppTheme.primary,
                                weight: FontWeight.w700)),
                      ),
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
                                          googleIdentity, 'Google'),
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
                    '휴대폰은 계정의 기본 식별 수단이라 항상 유지돼요.\n'
                    'Google 연결을 추가하면 그 계정으로도 로그인할 수 있어요.',
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

  String _formatPhone(String phone) {
    if (phone.length != 11) return phone;
    return '${phone.substring(0, 3)}-${phone.substring(3, 7)}-${phone.substring(7)}';
  }
}