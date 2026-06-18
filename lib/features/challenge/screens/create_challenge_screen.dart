import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/challenge.dart';
import '../services/challenge_service.dart';
import '../widgets/inline_range_calendar.dart';

/// 챌린지 만들기 화면 (v2 — 인라인 캘린더)
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

  @override
  Widget build(BuildContext context) {
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

              // ---- 기간 (인라인 캘린더) ----
              _label('기간'),
              Text(
                '날짜를 두 번 눌러 시작일과 종료일을 선택해 주세요',
                style: AppTheme.body(
                    size: 12, color: AppTheme.textLight),
              ),
              const SizedBox(height: 8),
              InlineRangeCalendar(
                initialRange: _period,
                onRangeChanged: (range) {
                  setState(() => _period = range);
                },
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