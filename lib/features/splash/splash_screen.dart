import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/ban_check.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../home/home_shell.dart';

/// 스플래시 화면
/// 1.2초 동안 로고를 보여준 뒤 Supabase 세션 유무에 따라 분기한다.
/// - 세션 있음 → HomeShell
/// - 세션 없음 → LoginScreen
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _decideNext();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decideNext() async {
    // 로고 노출 최소 시간
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final auth = ref.read(authServiceProvider);
    final loggedIn = auth.currentSession != null;
    print('[SPLASH] 세션: ${loggedIn ? "있음 → 홈" : "없음 → 로그인"}');

    // 정지 계정 체크 (정지면 안내 후 로그아웃, 로그인 화면으로)
    if (loggedIn) {
      final banned = await BanCheck.checkAndHandle(context);
      if (!mounted) return;
      if (banned) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => loggedIn ? const HomeShell() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.sunsetGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: AppTheme.warmGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusL),
                  ),
                  child: const Icon(
                    Icons.home_rounded,
                    size: 48,
                    color: AppTheme.textOnPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Text('교랑빌리지', style: AppTheme.display(size: 34)),
                const SizedBox(height: 8),
                Text(
                  '같은 마음이 모이는 마을',
                  style: AppTheme.body(size: 14, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}