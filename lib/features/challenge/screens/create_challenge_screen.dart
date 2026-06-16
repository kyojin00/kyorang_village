import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/challenge.dart';
import '../services/challenge_service.dart';

/// 챌린지 만들기 화면
/// 생성 성공 시 Challenge를 pop 결과로 반환한다.
class CreateChallengeScreen extends ConsumerStatefulWidget {
  const CreateChallengeScreen({super.key, required this.villageId});

  final String villageId;

  @override
  ConsumerState<CreateChallengeScreen> createState() =>
      _CreateChallengeScreenState();
}

class _CreateChallengeScreenState
    extends ConsumerState<CreateChallengeScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  DateTimeRange? _period;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _titleController.text.trim().length >= 2 &&
      _period != null &&
      !_submitting;

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _pickPeriod() async {
    final today = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _period,
      helpText: '챌린지 기간을 선택하세요',
      saveText: '확인',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: AppTheme.textOnPrimary,
              surface: AppTheme.bgCard,
              onSurface: AppTheme.textMain,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;

    if (picked.duration.inDays + 1 > 90) {
      _snack('챌린지는 최대 90일까지 가능해요.');
      return;
    }
    setState(() => _period = picked);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final challenge =
          await ref.read(challengeServiceProvider).createChallenge(
                villageId: widget.villageId,
                title: _titleController.text,
                description: _descController.text.trim().isEmpty
                    ? null
                    : _descController.text,
                startDate: _period!.start,
                endDate: _period!.end,
              );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${challenge.title} 챌린지가 시작돼요!')),
      );
      Navigator.of(context).pop(challenge);
    } catch (e) {
      print('[CREATE_CHALLENGE] 생성 실패: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('챌린지를 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
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
    final period = _period;
    final periodText = period == null
        ? '기간을 선택하세요'
        : '${period.start.month}.${period.start.day} ~ '
            '${period.end.month}.${period.end.day} '
            '(${period.duration.inDays + 1}일)';

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: const Text('챌린지 만들기')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('어떤 도전인가요?', style: AppTheme.display(size: 24)),
              const SizedBox(height: 20),

              // ---- 제목 ----
              _label('챌린지 이름'),
              TextField(
                controller: _titleController,
                maxLength: 30,
                style: AppTheme.body(size: 15, weight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '예: 매일 아침 스트레칭 10분',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              // ---- 기간 ----
              _label('기간'),
              InkWell(
                onTap: _submitting ? null : _pickPeriod,
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 20, color: AppTheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        periodText,
                        style: AppTheme.body(
                          size: 14,
                          color: period == null
                              ? AppTheme.textLight
                              : AppTheme.textMain,
                          weight: period == null
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- 소개 ----
              _label('소개 (선택)'),
              TextField(
                controller: _descController,
                maxLines: 3,
                maxLength: 100,
                style: AppTheme.body(size: 14),
                decoration: const InputDecoration(
                  hintText: '어떻게 인증하면 되는지 알려 주세요',
                ),
              ),
              const SizedBox(height: 24),

              // ---- 생성 버튼 ----
              ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.textOnPrimary,
                        ),
                      )
                    : const Text('챌린지 시작하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTheme.body(
          size: 13,
          color: AppTheme.textSub,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}