import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../home/home_shell.dart';
import '../models/village.dart';
import '../services/village_service.dart';
import 'village_detail_screen.dart';

/// 내 마을 탭 - 가입한 마을 목록
class MyVillagesTab extends ConsumerWidget {
  const MyVillagesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myVillages = ref.watch(myVillagesProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text('내 마을', style: AppTheme.display(size: 28)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: myVillages.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) {
                  print('[MY_VILLAGES] 조회 실패: $e');
                  return _ErrorView(
                    onRetry: () => ref.invalidate(myVillagesProvider),
                  );
                },
                data: (villages) {
                  if (villages.isEmpty) {
                    return _EmptyView(
                      onExplore: () => ref
                          .read(homeTabIndexProvider.notifier)
                          .set(1), // 탐색 탭으로
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(myVillagesProvider.notifier).refresh(),
                    color: AppTheme.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: villages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) =>
                          _MyVillageCard(village: villages[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 내 마을 카드
class _MyVillageCard extends ConsumerWidget {
  const _MyVillageCard({required this.village});

  final Village village;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = village.categoryInfo;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VillageDetailScreen(village: village),
            ),
          );
          // 상세에서 탈퇴/삭제했을 수 있으니 돌아오면 갱신
          ref.invalidate(myVillagesProvider);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppTheme.warmGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                alignment: Alignment.center,
                child:
                    Text(cat.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      village.name,
                      style:
                          AppTheme.body(size: 15, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${cat.label} · ${village.memberCount}명이 함께해요',
                      style:
                          AppTheme.body(size: 12, color: AppTheme.textSub),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 빈 상태 - 탐색 탭으로 유도
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏡', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 16),
            Text('아직 가입한 마을이 없어요', style: AppTheme.display(size: 22)),
            const SizedBox(height: 8),
            Text(
              '관심사가 비슷한 이웃들이\n기다리고 있어요',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 14,
                color: AppTheme.textSub,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              child: ElevatedButton(
                onPressed: onExplore,
                child: const Text('마을 둘러보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 에러 상태
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '마을 목록을 불러오지 못했어요',
            style: AppTheme.body(size: 14, color: AppTheme.textSub),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}