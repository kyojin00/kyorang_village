import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../village/models/village.dart';
import '../models/challenge.dart';
import '../services/challenge_service.dart';
import 'challenge_detail_screen.dart';
import 'create_challenge_screen.dart';

/// 마을 챌린지 목록 화면
class ChallengeListScreen extends ConsumerStatefulWidget {
  const ChallengeListScreen({super.key, required this.village});

  final Village village;

  @override
  ConsumerState<ChallengeListScreen> createState() =>
      _ChallengeListScreenState();
}

class _ChallengeListScreenState
    extends ConsumerState<ChallengeListScreen> {
  List<Challenge> _challenges = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await ref
          .read(challengeServiceProvider)
          .fetchChallenges(widget.village.id);
      if (!mounted) return;
      setState(() {
        _challenges = list;
        _loading = false;
      });
    } catch (e) {
      print('[CHALLENGE_LIST] 조회 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('챌린지를 불러오지 못했어요.')),
      );
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<Challenge>(
      MaterialPageRoute(
        builder: (_) => CreateChallengeScreen(villageId: widget.village.id),
      ),
    );
    if (created == null || !mounted) return;

    setState(() => _challenges.insert(0, created));
    _openDetail(created);
  }

  Future<void> _openDetail(Challenge challenge) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChallengeDetailScreen(challenge: challenge),
      ),
    );
    // 상세에서 참가/인증/삭제했을 수 있으니 갱신
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: Text('${widget.village.name} 챌린지')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textOnPrimary,
        icon: const Icon(Icons.flag_rounded),
        label: const Text('챌린지 만들기'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _challenges.isEmpty
                ? _emptyView()
                : RefreshIndicator(
                    onRefresh: _fetch,
                    color: AppTheme.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                      itemCount: _challenges.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) =>
                          _challengeCard(_challenges[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _challengeCard(Challenge challenge) {
    final status = challenge.status;
    final statusColor = switch (status) {
      ChallengeStatus.active => AppTheme.secondary,
      ChallengeStatus.upcoming => AppTheme.accent,
      ChallengeStatus.ended => AppTheme.textLight,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        onTap: () => _openDetail(challenge),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusFull),
                    ),
                    child: Text(
                      status.label,
                      style: AppTheme.body(
                        size: 11,
                        color: statusColor,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    challenge.periodLabel,
                    style:
                        AppTheme.body(size: 12, color: AppTheme.textSub),
                  ),
                  const Spacer(),
                  if (challenge.hasCheckedInToday)
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: AppTheme.secondaryDark),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                challenge.title,
                style: AppTheme.body(size: 16, weight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '${challenge.participantCount}명 도전 중',
                style: AppTheme.body(size: 12, color: AppTheme.textSub),
              ),
              if (challenge.isParticipating) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        child: LinearProgressIndicator(
                          value: challenge.myProgress,
                          minHeight: 6,
                          backgroundColor: AppTheme.bgSoft,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${challenge.myCheckinCount}/${challenge.totalDays}일',
                      style: AppTheme.body(
                        size: 11,
                        color: AppTheme.primaryDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🚩', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            '아직 챌린지가 없어요\n이웃들과 함께 도전을 시작해 보세요!',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 14,
              color: AppTheme.textSub,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}