import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/challenge.dart';

/// 챌린지 목록용 카드 (v2 — 장식적 디자인)
///
/// 디자인 원칙:
///   - 상태에 따라 카드 분위기가 달라짐
///     active: 따뜻한 코랄 톤, 살짝 강조
///     upcoming: 차분한 베이지
///     ended: 무채색
///   - 챌린지 첫 글자를 큰 이모지/장식으로 사용
///   - 진행률은 미니 도트 시리즈로 (한눈에 보임)
///   - 오늘 인증 안 한 활성 챌린지엔 부드러운 알림 점
class ChallengeListCard extends StatelessWidget {
  const ChallengeListCard({
    super.key,
    required this.challenge,
    required this.onTap,
  });

  final Challenge challenge;
  final VoidCallback onTap;

  // ---------- 상태별 컬러 팔레트 ----------

  _Palette get _palette {
    switch (challenge.status) {
      case ChallengeStatus.active:
        return const _Palette(
          bg: Color(0xFFFFF1E8),
          accent: AppTheme.primary,
          accentDark: AppTheme.primaryDark,
          stripe: Color(0xFFFFE0D0),
        );
      case ChallengeStatus.upcoming:
        return const _Palette(
          bg: Color(0xFFFFFBF3),
          accent: AppTheme.accent,
          accentDark: Color(0xFFB8924A),
          stripe: Color(0xFFFFF1D8),
        );
      case ChallengeStatus.ended:
        return _Palette(
          bg: AppTheme.bgSoft,
          accent: AppTheme.textLight,
          accentDark: AppTheme.textSub,
          stripe: const Color(0xFFEEEEEE),
        );
    }
  }

  /// 챌린지 제목 첫 글자가 이모지면 그대로, 아니면 카테고리별 기본 이모지
  String get _emoji {
    final first = challenge.title.runes.isNotEmpty
        ? String.fromCharCode(challenge.title.runes.first)
        : '';
    // 이모지 범위 대충 체크 (Surrogates까지 안 정확하지만 일단)
    final code = first.runes.firstOrNull ?? 0;
    final isEmoji = code > 0x2600;
    if (isEmoji) return first;
    return '🚩'; // 기본
  }

  /// 상태 라벨 + 색
  String get _statusLabel {
    return switch (challenge.status) {
      ChallengeStatus.active => '진행 중',
      ChallengeStatus.upcoming => '시작 전',
      ChallengeStatus.ended => '종료',
    };
  }

  /// 진행률 도트 — 항상 7개 보여줌 (챌린지 길이와 무관하게 진행률만 표현)
  List<bool> get _progressDots {
    const dots = 7;
    final filled = (challenge.myProgress * dots).round();
    return List.generate(dots, (i) => i < filled);
  }

  bool get _needsTodayCheckin =>
      challenge.status == ChallengeStatus.active &&
      challenge.isParticipating &&
      !challenge.hasCheckedInToday;

  @override
  Widget build(BuildContext context) {
    final p = _palette;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            border: Border.all(
              color: p.accent.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              // ---- 배경 장식: 오른쪽 위에 큰 이모지 (반투명) ----
              Positioned(
                top: -10,
                right: -8,
                child: Opacity(
                  opacity: 0.18,
                  child: Text(
                    _emoji,
                    style: const TextStyle(fontSize: 78),
                  ),
                ),
              ),

              // ---- 메인 콘텐츠 ----
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 상태 칩
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.2),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          child: Text(
                            _statusLabel,
                            style: AppTheme.body(
                              size: 11,
                              color: p.accentDark,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          challenge.periodLabel,
                          style: AppTheme.body(
                              size: 12, color: AppTheme.textSub),
                        ),
                        const Spacer(),
                        if (_needsTodayCheckin)
                          // 오늘 인증 안 함 — 부드러운 빨간 점
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.error,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (challenge.hasCheckedInToday)
                          const Icon(Icons.check_circle_rounded,
                              size: 18,
                              color: AppTheme.secondaryDark),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 이모지 + 제목
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusM),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                challenge.title,
                                style: AppTheme.body(
                                    size: 16, weight: FontWeight.w700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${challenge.participantCount}명 도전 중',
                                style: AppTheme.body(
                                    size: 12,
                                    color: AppTheme.textSub),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ---- 진행 도트 (참가자만) ----
                    if (challenge.isParticipating) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          // 7개 도트
                          ..._progressDots.map((filled) => Padding(
                                padding:
                                    const EdgeInsets.only(right: 4),
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: filled
                                        ? p.accent
                                        : p.stripe,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )),
                          const Spacer(),
                          Text(
                            '${challenge.myCheckinCount}/${challenge.totalDays}일',
                            style: AppTheme.body(
                              size: 11,
                              color: p.accentDark,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Palette {
  const _Palette({
    required this.bg,
    required this.accent,
    required this.accentDark,
    required this.stripe,
  });

  final Color bg;
  final Color accent;
  final Color accentDark;
  final Color stripe;
}