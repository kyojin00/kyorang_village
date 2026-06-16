import 'package:flutter/material.dart';

import '../services/safety_service.dart';
import '../theme/app_theme.dart';

/// 공용 신고 다이얼로그
/// 게시글, 댓글, 메시지 등 어떤 콘텐츠든 이 함수 하나로 신고한다.
///
/// 사용 예:
///   showReportDialog(
///     context,
///     targetType: ReportTargetType.post,
///     targetId: post.id,
///     targetLabel: '게시글',
///   );
Future<void> showReportDialog(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
  String? targetLabel,
}) async {
  final label = targetLabel ?? targetType.label;

  final reason = await showDialog<ReportReason>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
      ),
      title: Text(
        '$label 신고',
        style: AppTheme.body(size: 16, weight: FontWeight.w700),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            '신고 사유를 선택해 주세요.',
            style: AppTheme.body(size: 13, color: AppTheme.textSub),
          ),
        ),
        ...ReportReason.values.map(
          (r) => SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(r),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Text(r.label, style: AppTheme.body(size: 14)),
          ),
        ),
      ],
    ),
  );

  if (reason == null || !context.mounted) return;

  try {
    await SafetyService.instance.report(
      targetType: targetType,
      targetId: targetId,
      reason: reason,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('신고가 접수됐어요. 빠르게 확인할게요.')),
      );
  } catch (e) {
    print('[REPORT] 신고 실패: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('신고를 접수하지 못했어요.')),
      );
  }
}