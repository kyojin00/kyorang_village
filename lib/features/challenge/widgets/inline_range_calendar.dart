import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 인라인 월 캘린더 — 두 번 탭으로 기간 선택
///
/// 사용 흐름:
///   1. 첫 탭: 시작일 선택
///   2. 두 번째 탭: 종료일 선택 (시작일 이후)
///   3. 다시 탭: 새 시작일 (선택 초기화)
///
/// 시각:
///   - 시작일/종료일: 진한 주황 원
///   - 그 사이: 연한 주황 배경
///   - 오늘: 작은 점
///   - 과거 날짜: 회색 (선택 불가)
class InlineRangeCalendar extends StatefulWidget {
  const InlineRangeCalendar({
    super.key,
    this.initialRange,
    required this.onRangeChanged,
    this.maxDays = 90,
  });

  final DateTimeRange? initialRange;
  final ValueChanged<DateTimeRange?> onRangeChanged;

  /// 최대 기간 (일)
  final int maxDays;

  @override
  State<InlineRangeCalendar> createState() => _InlineRangeCalendarState();
}

class _InlineRangeCalendarState extends State<InlineRangeCalendar> {
  late DateTime _month; // 현재 보고 있는 달 (1일 기준)
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _month = DateTime(today.year, today.month);
    _start = widget.initialRange?.start;
    _end = widget.initialRange?.end;
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInRange(DateTime d) {
    if (_start == null || _end == null) return false;
    return d.isAfter(_start!) && d.isBefore(_end!);
  }

  bool _isPast(DateTime d) {
    final today = _dateOnly(DateTime.now());
    return d.isBefore(today);
  }

  void _onTapDay(DateTime day) {
    if (_isPast(day)) return;

    setState(() {
      // 시작일이 없거나, 둘 다 선택된 상태 → 시작일 새로 지정
      if (_start == null || (_start != null && _end != null)) {
        _start = day;
        _end = null;
      }
      // 시작일만 있는 상태 → 종료일 지정
      else {
        if (day.isBefore(_start!)) {
          // 시작일보다 이전 탭 → 시작일을 그 날짜로 재지정
          _start = day;
          _end = null;
        } else if (_isSameDay(day, _start!)) {
          // 같은 날 다시 탭 → 1일짜리 챌린지
          _end = day;
        } else {
          // 최대 기간 검증
          final days = day.difference(_start!).inDays + 1;
          if (days > widget.maxDays) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text('챌린지는 최대 ${widget.maxDays}일까지 가능해요.'),
              ));
            return;
          }
          _end = day;
        }
      }
    });

    if (_start != null && _end != null) {
      widget.onRangeChanged(DateTimeRange(start: _start!, end: _end!));
    } else {
      widget.onRangeChanged(null);
    }
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 10),
          _buildWeekdayRow(),
          const SizedBox(height: 4),
          _buildGrid(),
          if (_start != null) ...[
            const SizedBox(height: 12),
            _buildSelectionSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: _prevMonth,
          icon: const Icon(Icons.chevron_left_rounded,
              color: AppTheme.textSub),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        Text(
          '${_month.year}년 ${_month.month}월',
          style: AppTheme.body(size: 15, weight: FontWeight.w700),
        ),
        IconButton(
          onPressed: _nextMonth,
          icon: const Icon(Icons.chevron_right_rounded,
              color: AppTheme.textSub),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }

  Widget _buildWeekdayRow() {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    return Row(
      children: List.generate(7, (i) {
        Color color = AppTheme.textLight;
        if (i == 0) color = AppTheme.error; // 일요일 빨강
        return Expanded(
          child: Center(
            child: Text(
              labels[i],
              style: AppTheme.body(
                size: 11,
                color: color,
                weight: FontWeight.w600,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildGrid() {
    // 이번 달 1일의 요일 (Dart: 1=월, 7=일)
    // 우리 격자는 일요일 시작이라 보정 필요
    final firstDay = DateTime(_month.year, _month.month, 1);
    final firstWeekday = firstDay.weekday % 7; // 일요일=0
    final daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final today = _dateOnly(DateTime.now());

    final cells = <Widget>[];

    // 빈 칸 (이번 달 1일이 시작되는 요일까지)
    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const _EmptyCell());
    }

    // 날짜
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(_month.year, _month.month, d);
      final isStart = _start != null && _isSameDay(day, _start!);
      final isEnd = _end != null && _isSameDay(day, _end!);
      final inRange = _isInRange(day);
      final isToday = _isSameDay(day, today);
      final past = _isPast(day);

      cells.add(_DayCell(
        day: d,
        isStart: isStart,
        isEnd: isEnd,
        inRange: inRange,
        isToday: isToday,
        isPast: past,
        weekday: day.weekday,
        onTap: () => _onTapDay(day),
      ));
    }

    // 7개씩 줄 만들기
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final row = cells.sublist(
          i, (i + 7).clamp(0, cells.length));
      // 마지막 줄 빈칸 채우기
      while (row.length < 7) {
        row.add(const _EmptyCell());
      }
      rows.add(Row(children: row.map((c) => Expanded(child: c)).toList()));
    }

    return Column(children: rows);
  }

  Widget _buildSelectionSummary() {
    String text;
    if (_start != null && _end == null) {
      text = '${_start!.month}.${_start!.day} 선택됨 — 종료일을 골라 주세요';
    } else if (_start != null && _end != null) {
      final days = _end!.difference(_start!).inDays + 1;
      text = '${_start!.month}.${_start!.day} ~ '
          '${_end!.month}.${_end!.day} '
          '($days일)';
    } else {
      text = '';
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available_rounded,
              size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(
                size: 13,
                color: AppTheme.primaryDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 40);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isStart,
    required this.isEnd,
    required this.inRange,
    required this.isToday,
    required this.isPast,
    required this.weekday,
    required this.onTap,
  });

  final int day;
  final bool isStart;
  final bool isEnd;
  final bool inRange;
  final bool isToday;
  final bool isPast;
  final int weekday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = isStart || isEnd;
    final isSingleDay = isStart && isEnd;

    // 색상 결정
    Color textColor = AppTheme.textMain;
    if (isPast) {
      textColor = AppTheme.textLight;
    } else if (isSelected) {
      textColor = Colors.white;
    } else if (weekday == DateTime.sunday) {
      textColor = AppTheme.error;
    }

    return GestureDetector(
      onTap: isPast ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 40,
        child: Stack(
          children: [
            // ---- 범위 배경 (시작일과 종료일 사이) ----
            if (inRange)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: AppTheme.primary.withValues(alpha: 0.15),
              ),
            // ---- 시작일 끝 처리 (오른쪽만 둥글지 않게) ----
            if (isStart && !isSingleDay)
              Positioned(
                right: 0,
                top: 6,
                bottom: 6,
                left: 20,
                child: Container(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                ),
              ),
            if (isEnd && !isSingleDay)
              Positioned(
                left: 0,
                top: 6,
                bottom: 6,
                right: 20,
                child: Container(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                ),
              ),
            // ---- 선택된 날짜 원형 강조 ----
            Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: !isSelected && isToday
                      ? Border.all(color: AppTheme.primary, width: 1.5)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: AppTheme.body(
                    size: 13,
                    color: textColor,
                    weight: isSelected || isToday
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}