import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_shell.dart';

/// 신규 가입자 닉네임 온보딩 화면
/// 휴대폰 인증으로 새 계정이 만들어진 직후 1회만 표시.
class NicknameOnboardingScreen extends ConsumerStatefulWidget {
  const NicknameOnboardingScreen({super.key});

  @override
  ConsumerState<NicknameOnboardingScreen> createState() =>
      _NicknameOnboardingScreenState();
}

class _NicknameOnboardingScreenState
    extends ConsumerState<NicknameOnboardingScreen> {
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  bool get _canSave {
    final n = _nicknameController.text.trim();
    return n.length >= 2 && n.length <= 12;
  }

  Future<void> _save() async {
    final uid = AuthService.instance.currentUserId;
    if (uid == null) return;
    if (!_canSave) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'nickname': _nicknameController.text.trim(),
        'bio': _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
      }).eq('id', uid);

      // 알림 권한 요청 + FCM 토큰 저장 (실패해도 가입은 진행)
      try {
        await NotificationService.instance.requestPermission();
        await NotificationService.instance.saveToken();
      } catch (e) {
        print('[ONBOARDING] FCM 설정 실패 (계속 진행): $e');
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } catch (e) {
      print('[ONBOARDING] 저장 실패: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('저장에 실패했어요. 잠시 후 다시 시도해 주세요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppTheme.warmGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 34,
                  color: AppTheme.textOnPrimary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '마을에서 어떻게\n불러드릴까요?',
                style: AppTheme.display(size: 30),
              ),
              const SizedBox(height: 10),
              Text(
                '이웃들에게 보일 닉네임과\n한 줄 소개를 알려 주세요',
                style:
                    AppTheme.body(size: 14, color: AppTheme.textSub),
              ),
              const SizedBox(height: 32),

              Text('닉네임',
                  style: AppTheme.body(
                      size: 12, color: AppTheme.textLight)),
              const SizedBox(height: 6),
              TextField(
                controller: _nicknameController,
                maxLength: 12,
                autofocus: true,
                style: AppTheme.body(size: 16, weight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '2~12자',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 20),
              Text('한 줄 소개 (선택)',
                  style: AppTheme.body(
                      size: 12, color: AppTheme.textLight)),
              const SizedBox(height: 6),
              TextField(
                controller: _bioController,
                maxLines: 2,
                maxLength: 60,
                style: AppTheme.body(size: 14),
                decoration: const InputDecoration(
                  hintText: '어떤 마을에 끌리는지, 무엇을 좋아하는지 등',
                  counterText: '',
                ),
              ),

              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: (_canSave && !_saving) ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.textOnPrimary,
                        ),
                      )
                    : const Text('시작하기'),
              ),

              const SizedBox(height: 16),
              Text(
                '나중에 마이 탭에서 언제든 바꿀 수 있어요.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                    size: 12, color: AppTheme.textLight),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}