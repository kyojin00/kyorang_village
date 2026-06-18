import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../home/home_shell.dart';

/// 신규 사용자에게 앱 소개를 보여주는 온보딩 화면
///
/// 3장 PageView. 한 번 보면 Hive settings 박스에 기록되어 다시 안 보임.
/// 첫 로그인 후 NicknameOnboardingScreen 다음에 한 번만 표시.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Hive settings 박스 키 — 온보딩 본 적 있는지 표시
  static const String _seenKey = 'onboarding_seen_v1';

  /// 사용자가 이 화면을 본 적이 있는지 확인
  static bool hasSeenOnboarding() {
    try {
      final box = Hive.box<String>('settings');
      return box.get(_seenKey) == 'true';
    } catch (e) {
      print('[ONBOARDING] 확인 실패: $e');
      return false;
    }
  }

  /// 본 적 있다고 표시
  static Future<void> markAsSeen() async {
    try {
      final box = Hive.box<String>('settings');
      await box.put(_seenKey, 'true');
    } catch (e) {
      print('[ONBOARDING] 저장 실패: $e');
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      emoji: '🏘️',
      title: '관심사로 모이는\n작은 마을',
      description:
          '책, 운동, 게임, 반려동물처럼\n좋아하는 것끼리 모인 12개의 마을이\n빌리지에서 여러분을 기다려요.',
    ),
    _OnboardingPage(
      emoji: '🤝',
      title: '평평한 이웃 관계',
      description:
          '인기 순위도, 인플루언서도 없어요.\n모두가 동등한 이웃으로\n편안하게 이야기 나눠요.',
    ),
    _OnboardingPage(
      emoji: '🌱',
      title: '함께 해보는 챌린지',
      description:
          '혼자보다 함께가 더 즐거워요.\n이웃들과 매일 작은 도전을\n같이 인증하고 응원해 보세요.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLastPage => _currentPage == _pages.length - 1;

  Future<void> _next() async {
    if (_isLastPage) {
      await OnboardingScreen.markAsSeen();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _skip() async {
    await OnboardingScreen.markAsSeen();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 우측 건너뛰기
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _skip,
                    child: Text(
                      '건너뛰기',
                      style: AppTheme.body(
                        size: 13,
                        color: AppTheme.textLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 페이지
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _pages[i],
              ),
            ),

            // 페이지 도트
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.primary
                          : AppTheme.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // 하단 다음/시작 버튼
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(_isLastPage ? '시작하기' : '다음'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.emoji,
    required this.title,
    required this.description,
  });

  final String emoji;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 이모지 영역
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              gradient: AppTheme.warmGradient,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 64)),
          ),
          const SizedBox(height: 40),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTheme.display(size: 26),
          ),
          const SizedBox(height: 20),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 15,
              color: AppTheme.textSub,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}