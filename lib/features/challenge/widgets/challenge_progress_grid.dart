import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/challenge.dart';

/// 챌린지 진행 그리드 — N일 챌린지면 N칸을 격자로 표시
///
/// 각 칸:
///   - 인증한 날: 진한 주황 + 체크
///   - 인증 안 한 날 (지난 날): 회색
///   - 오늘 (아직 인증 안 함): 점선 테두리
///   - 미래: 옅은 회색
///
/// 챌린지가 7일 이하 → 한 줄에 다 표시
/// 7~14일 → 7칸씩 두 줄
/// 그 이상 → 7칸씩 여러 줄
class ChallengeProgressGrid extends StatelessWidget {
  const ChallengeProgressGrid({
    super.key,
    required this.challenge,
    required this.myCheckedDates,
  });

  final Challenge challenge;

  /// 본인이 인증한 날짜 집합 (date only)
  final Set<DateTime> myCheckedDates;

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final start = _dateOnly(challenge.startDate);
    final today = _dateOnly(DateTime.now());
    final total = challenge.totalDays;

    // 일별 상태 계산
    final cells = <_CellData>[];
    for (var i = 0; i < total; i++) {
      final day = start.add(Duration(days: i));
      final checked = myCheckedDates.any((d) => _isSameDay(d, day));
      _CellStatus status;
      if (checked) {
        status = _CellStatus.checked;
      } else if (day.isAfter(today)) {
        status = _CellStatus.future;
      } else if (_isSameDay(day, today)) {
        status = _CellStatus.todayMissed;
      } else {
        status = _CellStatus.missed;
      }
      cells.add(_CellData(dayIndex: i + 1, date: day, status: status));
    }

    // 칸 크기 계산 — 총 일수에 따라 다르게
    // 7개 이하: 큰 칸 (한 줄)
    // 8~31: 7칸씩 격자
    // 32~90: 10칸씩 격자 (더 작게)
    final perRow = total <= 7 ? total : (total <= 31 ? 7 : 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- 상단 요약 ----
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '인증 현황',
              style: AppTheme.body(
                size: 12,
                color: AppTheme.textSub,
                weight: FontWeight.w600,
              ),
            ),
            Text(
              '${challenge.myCheckinCount}/${challenge.totalDays}일',
              style: AppTheme.body(
                size: 12,
                color: AppTheme.primaryDark,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ---- 격자 ----
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 4.0;
            final cellSize =
                (constraints.maxWidth - gap * (perRow - 1)) / perRow;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: cells
                  .map((c) => _Cell(
                        data: c,
                        size: cellSize,
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

enum _CellStatus {
  checked, // 인증함
  missed, // 인증 못 한 과거
  todayMissed, // 오늘 (아직 안 함)
  future, // 미래
}

class _CellData {
  const _CellData({
    required this.dayIndex,
    required this.date,
    required this.status,
  });

  final int dayIndex;
  final DateTime date;
  final _CellStatus status;
}

class _Cell extends StatelessWidget {
  const _Cell({required this.data, required this.size});

  final _CellData data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: _build(),
    );
  }

  Widget _build() {
    switch (data.status) {
      case _CellStatus.checked:
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_rounded,
            size: size * 0.55,
            color: Colors.white,
          ),
        );
      case _CellStatus.missed:
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bgSoft,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '${data.dayIndex}',
            style: TextStyle(
              fontSize: size * 0.35,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case _CellStatus.todayMissed:
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppTheme.primary,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '${data.dayIndex}',
            style: TextStyle(
              fontSize: size * 0.35,
              color: AppTheme.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case _CellStatus.future:
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bgSoft.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '${data.dayIndex}',
            style: TextStyle(
              fontSize: size * 0.32,
              color: AppTheme.textLight.withValues(alpha: 0.5),
              fontWeight: FontWeight.w400,
            ),
          ),
        );
    }
  }
}