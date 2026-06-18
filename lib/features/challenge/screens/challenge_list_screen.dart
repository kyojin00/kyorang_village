import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../village/models/village.dart';
import '../models/challenge.dart';
import '../services/challenge_service.dart';
import '../widgets/challenge_list_card.dart';
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
                          const SizedBox(height: 14),
                      itemBuilder: (context, i) => ChallengeListCard(
                        challenge: _challenges[i],
                        onTap: () => _openDetail(_challenges[i]),
                      ),
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