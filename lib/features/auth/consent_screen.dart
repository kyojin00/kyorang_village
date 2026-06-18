import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import 'nickname_onboarding_screen.dart';

/// 약관 동의 화면 — 이메일/Google 가입 직후 닉네임 입력 전 1회 통과
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _marketing = false;
  bool _saving = false;

  bool get _canSubmit => _terms && _privacy;
  bool get _allChecked => _terms && _privacy && _marketing;

  void _toggleAll() {
    setState(() {
      final next = !_allChecked;
      _terms = next;
      _privacy = next;
      _marketing = next;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      _snack('링크를 열지 못했어요.');
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() => _saving = true);

    try {
      await Supabase.instance.client.rpc('save_consents', params: {
        'p_terms': _terms,
        'p_privacy': _privacy,
        'p_marketing': _marketing,
      });

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const NicknameOnboardingScreen()),
        (route) => false,
      );
    } catch (e) {
      print('[CONSENT] 저장 실패: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('저장에 실패했어요. 잠시 후 다시 시도해 주세요.');
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              _buildHeader(),
              const SizedBox(height: 28),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _allCheckRow(),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _consentRow(
                      label: '이용약관 동의',
                      required: true,
                      value: _terms,
                      onChanged: (v) => setState(() => _terms = v),
                      onOpen: () => _openUrl('https://kyorang.com/terms'),
                    ),
                    _consentRow(
                      label: '개인정보처리방침 동의',
                      required: true,
                      value: _privacy,
                      onChanged: (v) => setState(() => _privacy = v),
                      onOpen: () => _openUrl('https://kyorang.com/privacy'),
                    ),
                    _consentRow(
                      label: '마케팅 정보 수신',
                      required: false,
                      value: _marketing,
                      onChanged: (v) => setState(() => _marketing = v),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSoft,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusM),
                      ),
                      child: Text(
                        '교랑빌리지는 따뜻한 이웃 커뮤니티예요.\n'
                        '필수 약관에 동의해 주셔야 가입을 마칠 수 있어요.\n'
                        '마케팅 수신은 선택이며, 동의해 주시면 새 마을 추천 등을 알려드려요.',
                        style: AppTheme.body(
                          size: 12,
                          color: AppTheme.textLight,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: (_canSubmit && !_saving) ? _submit : null,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.textOnPrimary,
                        ),
                      )
                    : const Text('동의하고 시작하기'),
              ),
              const SizedBox(height: 24),
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
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppTheme.warmGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            size: 30,
            color: AppTheme.textOnPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '약관 동의',
          style: AppTheme.display(size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          '교랑빌리지를 시작하기 전에\n약관에 동의해 주세요',
          style: AppTheme.body(
              size: 14, color: AppTheme.textSub, height: 1.5),
        ),
      ],
    );
  }

  Widget _allCheckRow() {
    return InkWell(
      onTap: _toggleAll,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _allChecked
              ? AppTheme.primary.withOpacity(0.08)
              : AppTheme.bgSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          border: Border.all(
            color: _allChecked
                ? AppTheme.primary
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            _checkIcon(_allChecked, large: true),
            const SizedBox(width: 12),
            Text(
              '전체 동의',
              style: AppTheme.body(
                size: 15,
                weight: FontWeight.w700,
                color: _allChecked
                    ? AppTheme.primary
                    : AppTheme.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _consentRow({
    required String label,
    required bool required,
    required bool value,
    required ValueChanged<bool> onChanged,
    VoidCallback? onOpen,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppTheme.radiusS),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            _checkIcon(value),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: AppTheme.body(size: 14, color: AppTheme.textMain),
                  children: [
                    TextSpan(
                      text: required ? '(필수) ' : '(선택) ',
                      style: AppTheme.body(
                        size: 12,
                        color: required
                            ? AppTheme.primary
                            : AppTheme.textLight,
                        weight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: label),
                  ],
                ),
              ),
            ),
            if (onOpen != null)
              TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '보기',
                  style: AppTheme.body(
                    size: 12,
                    color: AppTheme.textLight,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _checkIcon(bool value, {bool large = false}) {
    final size = large ? 24.0 : 22.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: value ? AppTheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(
          color: value ? AppTheme.primary : AppTheme.divider,
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.check_rounded,
        size: size * 0.7,
        color: value ? Colors.white : Colors.transparent,
      ),
    );
  }
}