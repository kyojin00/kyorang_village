import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/ban_check.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_shell.dart';
import 'nickname_onboarding_screen.dart';

/// 로그인 화면 (전화번호 → OTP 2단계, Google 로그인 옵션)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with WidgetsBindingObserver {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  /// false: 전화번호 입력 단계 / true: OTP 입력 단계
  bool _otpStep = false;
  bool _loading = false;
  bool _googleLoading = false;
  String? _verificationId;

  /// 재발송 타이머
  Timer? _timer;
  int _remainSeconds = 0;

  /// Supabase auth 상태 구독 - Google OAuth 콜백 처리용
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Google OAuth는 브라우저로 갔다가 deep link로 돌아옴.
    // 돌아오면 onAuthStateChange로 SIGNED_IN 이벤트가 발생 → 홈으로 이동.
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn && _googleLoading) {
        setState(() => _googleLoading = false);
        _goHome();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 사용자가 브라우저에서 앱으로 돌아왔는데도 세션이 없으면
    // Google 첫 사용자가 서버 트리거에 거부된 것으로 간주.
    if (state == AppLifecycleState.resumed && _googleLoading) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || !_googleLoading) return;
        final session =
            Supabase.instance.client.auth.currentSession;
        if (session == null) {
          setState(() => _googleLoading = false);
          _showRejectedDialog();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _authSub?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ===========================================================
  // 액션 - 전화번호
  // ===========================================================

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final auth = ref.read(authServiceProvider);
    await auth.sendOtp(
      phone: _phoneController.text,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _otpStep = true;
          _loading = false;
        });
        _startTimer();
      },
      onAutoVerified: (result) {
        if (!mounted) return;
        _goNext(result);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showError(message);
      },
    );
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null) return;
    if (_otpController.text.trim().length != 6) {
      _showError('인증번호 6자리를 입력해 주세요.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final auth = ref.read(authServiceProvider);
    final result = await auth.verifyOtp(
      phone: _phoneController.text,
      verificationId: _verificationId!,
      smsCode: _otpController.text,
      onError: (message) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showError(message);
      },
    );

    if (result != null && mounted) _goNext(result);
  }

  // ===========================================================
  // 액션 - Google
  // ===========================================================

  Future<void> _signInWithGoogle() async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);

    try {
      await AuthService.instance.signInWithGoogle();
      // 브라우저로 빠지고 콜백은 onAuthStateChange로 받음.
      // 사용자가 브라우저에서 취소하고 돌아올 수도 있으니 타임아웃은 따로 안 둠.
    } catch (e) {
      print('[LOGIN] Google 로그인 실패: $e');
      if (!mounted) return;
      setState(() => _googleLoading = false);
      _showError('Google 로그인에 실패했어요.');
    }
  }

  void _goNext(AuthResult result) async {
    // 정지 계정이면 안내 후 차단
    final banned = await BanCheck.checkAndHandle(context);
    if (banned || !mounted) return;

    if (result == AuthResult.signedUp) {
      // 신규 가입 → 닉네임 온보딩 (그 안에서 권한 요청 + 토큰 저장)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const NicknameOnboardingScreen()),
        (route) => false,
      );
    } else {
      // 기존 사용자 → 토큰 저장만 (권한은 이미 받았다고 가정)
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

  /// Google OAuth 콜백 후 호출. Google은 기존 연결된 user만 통과하므로 항상 기존.
  void _goHome() async {
    final banned = await BanCheck.checkAndHandle(context);
    if (banned || !mounted) return;

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

  void _backToPhoneStep() {
    _timer?.cancel();
    setState(() {
      _otpStep = false;
      _loading = false;
      _verificationId = null;
      _otpController.clear();
      _remainSeconds = 0;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _remainSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remainSeconds <= 1) {
        t.cancel();
        setState(() => _remainSeconds = 0);
      } else {
        setState(() => _remainSeconds -= 1);
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Google 첫 사용자가 서버에 거부됐을 때 안내
  void _showRejectedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('휴대폰 인증이 먼저예요',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '교랑빌리지는 휴대폰 인증으로 시작해요.\n'
          '먼저 휴대폰 번호로 가입한 뒤, 마이 탭에서 Google 계정을 연결하면\n'
          '다음부터 Google로도 로그인할 수 있어요.',
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
              const SizedBox(height: 40),
              if (!_otpStep) _buildPhoneStep() else _buildOtpStep(),
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
        Text('교랑빌리지에\n어서 오세요!', style: AppTheme.display(size: 30)),
        const SizedBox(height: 10),
        Text(
          _otpStep
              ? '문자로 받은 인증번호 6자리를 입력해 주세요'
              : '휴대폰 번호로 간단하게 시작해요',
          style: AppTheme.body(size: 14, color: AppTheme.textSub),
        ),
      ],
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          style: AppTheme.body(size: 16, weight: FontWeight.w600),
          decoration: const InputDecoration(
            hintText: '01012345678',
            prefixIcon: Icon(Icons.phone_iphone_rounded,
                color: AppTheme.textLight),
          ),
          onSubmitted: (_) => _loading ? null : _sendOtp(),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _loading ? null : _sendOtp,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.textOnPrimary,
                  ),
                )
              : const Text('인증번호 받기'),
        ),

        // ---- 구분선 + Google 로그인 ----
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(child: Divider(color: AppTheme.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '또는',
                style:
                    AppTheme.body(size: 12, color: AppTheme.textLight),
              ),
            ),
            const Expanded(child: Divider(color: AppTheme.divider)),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton(
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
                        size: 24, color: AppTheme.textMain),
                    const SizedBox(width: 6),
                    Text('Google로 로그인',
                        style: AppTheme.body(
                            size: 15, weight: FontWeight.w600)),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Text(
          '처음 가입하는 분은 휴대폰 인증으로 시작해 주세요.\n'
          'Google 로그인은 휴대폰 인증 후 마이 탭에서 연결한 분만 사용할 수 있어요.',
          textAlign: TextAlign.center,
          style: AppTheme.body(
              size: 11, color: AppTheme.textLight, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: AppTheme.body(size: 20, weight: FontWeight.w700),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '인증번호 6자리',
            counterText: '',
            suffixIcon: _remainSeconds > 0
                ? Padding(
                    padding: const EdgeInsets.only(right: 16, top: 16),
                    child: Text(
                      '$_remainSeconds초',
                      style: AppTheme.body(
                        size: 13,
                        color: AppTheme.primary,
                        weight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
          ),
          onSubmitted: (_) => _loading ? null : _verifyOtp(),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _loading ? null : _verifyOtp,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.textOnPrimary,
                  ),
                )
              : const Text('확인'),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _loading ? null : _backToPhoneStep,
              child: const Text('번호 다시 입력'),
            ),
            Container(
              width: 1,
              height: 14,
              color: AppTheme.divider,
            ),
            TextButton(
              onPressed: (_loading || _remainSeconds > 0) ? null : _sendOtp,
              child: Text(
                _remainSeconds > 0 ? '재발송 대기 중' : '인증번호 재발송',
              ),
            ),
          ],
        ),
      ],
    );
  }
}