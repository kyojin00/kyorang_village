import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/ban_check.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_shell.dart';
import 'consent_screen.dart';
import 'nickname_onboarding_screen.dart';

/// 로그인/회원가입 화면 (이메일 + Google)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { signIn, signUp }

class _LoginScreenState extends ConsumerState<LoginScreen>
    with WidgetsBindingObserver {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _loading = false;
  bool _googleLoading = false;
  bool _passwordVisible = false;

  /// 가입 후 확인 메일 발송된 상태
  bool _confirmationSent = false;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn && _googleLoading) {
        setState(() => _googleLoading = false);
        _goNextAfterAuth(isNewSignUp: _isNewSession(data.session));
      }
    });
  }

  /// 새 세션이 닉네임 없는 신규 가입인지 판단 (휴리스틱)
  bool _isNewSession(Session? session) {
    final user = session?.user;
    if (user == null) return false;
    try {
      final createdAt = DateTime.parse(user.createdAt);
      final diff = DateTime.now().toUtc().difference(createdAt);
      return diff.inMinutes < 2;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _googleLoading) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || !_googleLoading) return;
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          setState(() => _googleLoading = false);
          _showError('Google 로그인이 취소되었거나 실패했어요.');
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ===========================================================
  // 액션
  // ===========================================================

  void _toggleMode() {
    setState(() {
      _mode = _mode == _Mode.signIn ? _Mode.signUp : _Mode.signIn;
      _confirmationSent = false;
    });
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!_validateEmail(email)) {
      _showError('올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    if (password.length < 6) {
      _showError('비밀번호는 6자 이상이어야 해요.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      if (_mode == _Mode.signUp) {
        final result = await AuthService.instance.signUpWithEmail(
          email: email,
          password: password,
        );
        if (!mounted) return;

        if (result == SignUpStatus.confirmEmailSent) {
          setState(() {
            _loading = false;
            _confirmationSent = true;
          });
        } else if (result == SignUpStatus.signedIn) {
          await _goNextAfterAuth(isNewSignUp: true);
        } else {
          setState(() => _loading = false);
          _showError('가입에 실패했어요. 잠시 후 다시 시도해 주세요.');
        }
      } else {
        await AuthService.instance.signInWithEmail(
          email: email,
          password: password,
        );
        await _goNextAfterAuth(isNewSignUp: false);
      }
    } on AuthException catch (e) {
      print('[LOGIN] AuthException: ${e.message}');
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(_translateAuthError(e));
    } catch (e) {
      print('[LOGIN] 예외: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('로그인 중 오류가 발생했어요.');
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);

    try {
      await AuthService.instance.signInWithGoogle();
    } catch (e) {
      print('[LOGIN] Google 로그인 실패: $e');
      if (!mounted) return;
      setState(() => _googleLoading = false);
      _showError('Google 로그인에 실패했어요.');
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (!_validateEmail(email)) {
      _showError('이메일 주소를 먼저 입력해 주세요.');
      return;
    }

    try {
      await AuthService.instance.sendPasswordReset(email);
      if (!mounted) return;
      _showInfo('비밀번호 재설정 메일을 보냈어요.\n메일함을 확인해 주세요.');
    } catch (e) {
      print('[LOGIN] 비번 재설정 실패: $e');
      if (!mounted) return;
      _showError('재설정 메일을 보내지 못했어요.');
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _emailController.text.trim();
    if (!_validateEmail(email)) return;

    try {
      await AuthService.instance.resendConfirmation(email);
      if (!mounted) return;
      _showInfo('확인 메일을 다시 보냈어요.');
    } catch (e) {
      print('[LOGIN] 확인 메일 재발송 실패: $e');
      if (!mounted) return;
      _showError('재발송에 실패했어요.');
    }
  }

  /// 로그인/가입 성공 후 분기
  ///
  /// 순서:
  ///   1. 정지 계정 확인
  ///   2. 약관 동의 확인 → 미동의면 ConsentScreen
  ///   3. 닉네임 확인 → 없으면 NicknameOnboardingScreen
  ///   4. 정상 → HomeShell
  Future<void> _goNextAfterAuth({required bool isNewSignUp}) async {
    final banned = await BanCheck.checkAndHandle(context);
    if (banned || !mounted) return;

    final uid = AuthService.instance.currentUserId;
    if (uid == null) return;

    // 1. 약관 동의 확인
    bool hasConsents = false;
    try {
      final result = await Supabase.instance.client
          .rpc('has_required_consents');
      hasConsents = result == true;
    } catch (e) {
      print('[LOGIN] 약관 확인 실패 (미동의로 간주): $e');
      hasConsents = false;
    }

    if (!mounted) return;

    if (!hasConsents) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ConsentScreen()),
        (route) => false,
      );
      return;
    }

    // 2. 닉네임 확인
    bool needNickname = isNewSignUp;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('nickname')
          .eq('id', uid)
          .maybeSingle();
      final nickname = row?['nickname'] as String?;
      needNickname = nickname == null || nickname.isEmpty;
    } catch (e) {
      print('[LOGIN] 닉네임 확인 실패 (신규로 간주): $e');
      needNickname = true;
    }

    if (!mounted) return;

    if (needNickname) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const NicknameOnboardingScreen()),
        (route) => false,
      );
    } else {
      try {
        await NotificationService.instance.saveToken();
      } catch (e) {
        print('[LOGIN] FCM 토큰 저장 실패 (계속 진행): $e');
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    }
  }

  // ===========================================================
  // 유틸
  // ===========================================================

  bool _validateEmail(String s) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  String _translateAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login') ||
        msg.contains('invalid credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않아요.';
    }
    if (msg.contains('email not confirmed')) {
      return '이메일 확인이 아직 안 됐어요.\n메일함의 확인 링크를 눌러 주세요.';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already registered')) {
      return '이미 가입된 이메일이에요.';
    }
    if (msg.contains('weak password')) {
      return '비밀번호가 너무 약해요. 6자 이상으로 다시 만들어 주세요.';
    }
    if (msg.contains('rate limit')) {
      return '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.';
    }
    return '인증 오류: ${e.message}';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              _buildHeader(),
              const SizedBox(height: 36),
              if (_confirmationSent) _buildConfirmSentCard(),
              if (!_confirmationSent) ...[
                _buildEmailForm(),
                const SizedBox(height: 24),
                _buildDivider(),
                const SizedBox(height: 16),
                _buildGoogleButton(),
                const SizedBox(height: 24),
                _buildModeToggle(),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppTheme.warmGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          child: const Icon(
            Icons.home_rounded,
            size: 34,
            color: AppTheme.textOnPrimary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _mode == _Mode.signUp
              ? '교랑빌리지에\n어서 오세요!'
              : '다시 만나서 반가워요',
          style: AppTheme.display(size: 30),
        ),
        const SizedBox(height: 10),
        Text(
          _mode == _Mode.signUp
              ? '이메일로 가입하거나 Google 계정을 사용해 보세요'
              : '이메일 또는 Google로 로그인해 주세요',
          style: AppTheme.body(size: 14, color: AppTheme.textSub),
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          style: AppTheme.body(size: 15),
          decoration: const InputDecoration(
            hintText: '이메일',
            prefixIcon: Icon(Icons.email_outlined,
                color: AppTheme.textLight),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: !_passwordVisible,
          textInputAction: TextInputAction.done,
          style: AppTheme.body(size: 15),
          decoration: InputDecoration(
            hintText: _mode == _Mode.signUp
                ? '비밀번호 (6자 이상)'
                : '비밀번호',
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                color: AppTheme.textLight),
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppTheme.textLight,
                size: 20,
              ),
              onPressed: () => setState(
                  () => _passwordVisible = !_passwordVisible),
            ),
          ),
          onSubmitted: (_) => _loading ? null : _submit(),
        ),
        if (_mode == _Mode.signIn) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _sendPasswordReset,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '비밀번호를 잊으셨어요?',
                style: AppTheme.body(
                    size: 12, color: AppTheme.textLight),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.textOnPrimary,
                  ),
                )
              : Text(_mode == _Mode.signUp ? '가입하기' : '로그인'),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppTheme.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('또는',
              style: AppTheme.body(
                  size: 12, color: AppTheme.textLight)),
        ),
        const Expanded(child: Divider(color: AppTheme.divider)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return OutlinedButton(
      onPressed: _googleLoading ? null : _signInWithGoogle,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textMain,
        side: const BorderSide(color: AppTheme.divider),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
      ),
      child: _googleLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppTheme.primary),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.g_mobiledata_rounded,
                    size: 28, color: AppTheme.textMain),
                const SizedBox(width: 8),
                Text(
                  'Google로 계속하기',
                  style: AppTheme.body(
                      size: 15, weight: FontWeight.w600),
                ),
              ],
            ),
    );
  }

  Widget _buildModeToggle() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _mode == _Mode.signUp ? '이미 계정이 있나요?' : '아직 계정이 없나요?',
            style: AppTheme.body(size: 13, color: AppTheme.textSub),
          ),
          TextButton(
            onPressed: _loading ? null : _toggleMode,
            child: Text(
              _mode == _Mode.signUp ? '로그인' : '가입하기',
              style: AppTheme.body(
                size: 13,
                color: AppTheme.primary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmSentCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.bgSoft,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mark_email_read_outlined,
                      size: 22, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '확인 메일을 보냈어요',
                    style: AppTheme.body(
                        size: 16, weight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${_emailController.text.trim()} 주소로 확인 메일을 보냈어요.\n'
                '메일함에서 링크를 누른 뒤 다시 돌아와 로그인해 주세요.',
                style: AppTheme.body(
                    size: 13, color: AppTheme.textSub, height: 1.6),
              ),
              const SizedBox(height: 12),
              Text(
                '메일이 안 보이면 스팸함도 확인해 보세요.',
                style: AppTheme.body(
                    size: 12, color: AppTheme.textLight),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _resendConfirmation,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSub,
            side: const BorderSide(color: AppTheme.divider),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
          ),
          child: const Text('확인 메일 다시 보내기'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            setState(() {
              _confirmationSent = false;
              _mode = _Mode.signIn;
            });
          },
          child: Text(
            '로그인 화면으로 돌아가기',
            style: AppTheme.body(
                size: 13, color: AppTheme.textLight),
          ),
        ),
      ],
    );
  }
}