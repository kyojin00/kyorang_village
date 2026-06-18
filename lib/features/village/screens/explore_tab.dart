import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/village.dart';
import '../services/village_service.dart';
import 'create_village_screen.dart';
import 'village_detail_screen.dart';

/// 탐색 탭 - 마을 검색/필터/가입
class ExploreTab extends ConsumerStatefulWidget {
  const ExploreTab({super.key});

  @override
  ConsumerState<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends ConsumerState<ExploreTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Village> _villages = [];
  bool _loading = true;
  String? _selectedCategory;
  String _search = '';

  final Set<String> _joining = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ===========================================================
  // 데이터
  // ===========================================================

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(villageServiceProvider).fetchExploreVillages(
            category: _selectedCategory,
            search: _search,
          );
      if (!mounted) return;
      setState(() {
        _villages = list;
        _loading = false;
      });
    } catch (e) {
      print('[EXPLORE] 목록 조회 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('마을 목록을 불러오지 못했어요.');
    }
  }

  void _onSearchChanged(String value) {
    setState(() {}); // suffix 아이콘 갱신용
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = value;
      _fetch();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _search = '';
    _debounce?.cancel();
    _fetch();
  }

  void _onCategoryTap(String? code) {
    setState(() => _selectedCategory = code);
    _fetch();
  }

  Future<void> _join(Village village) async {
    if (_joining.contains(village.id)) return;
    setState(() => _joining.add(village.id));

    try {
      await ref.read(villageServiceProvider).joinVillage(village.id);
      ref.invalidate(myVillagesProvider);

      if (!mounted) return;
      setState(() {
        _joining.remove(village.id);
        final i = _villages.indexWhere((v) => v.id == village.id);
        if (i >= 0) {
          _villages[i] = _villages[i].copyWith(
            isJoined: true,
            memberCount: _villages[i].memberCount + 1,
          );
        }
      });
      _showSnack('${village.name} 마을에 가입했어요!');
    } catch (e) {
      print('[EXPLORE] 가입 실패: $e');
      if (!mounted) return;
      setState(() => _joining.remove(village.id));
      _showSnack('가입하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _openDetail(Village village) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VillageDetailScreen(village: village),
      ),
    );
    _fetch();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<Village>(
      MaterialPageRoute(builder: (_) => const CreateVillageScreen()),
    );
    if (created != null) {
      _fetch();
      if (!mounted) return;
      _openDetail(created);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textOnPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('마을 만들기'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text('탐색', style: AppTheme.display(size: 28)),
            ),
            const SizedBox(height: 12),

            // ---- 검색 ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: AppTheme.body(size: 14),
                decoration: InputDecoration(
                  hintText: '마을 이름·소개·관심사로 검색',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppTheme.textLight),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.close_rounded,
                              color: AppTheme.textLight, size: 18),
                          tooltip: '지우기',
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ---- 카테고리 칩 ----
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _categoryChip(label: '전체', code: null),
                  ...VillageCategory.all.map(
                    (c) => _categoryChip(
                      label: '${c.emoji} ${c.label}',
                      code: c.code,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ---- 목록 ----
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _villages.isEmpty
                      ? _emptyView()
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: AppTheme.primary,
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(20, 8, 20, 96),
                            itemCount: _villages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _villageCard(_villages[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip({required String label, required String? code}) {
    final selected = _selectedCategory == code;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _onCategoryTap(code),
        labelStyle: AppTheme.body(
          size: 13,
          color: selected ? AppTheme.textOnPrimary : AppTheme.textSub,
          weight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _villageCard(Village village) {
    final cat = village.categoryInfo;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        onTap: () => _openDetail(village),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.bgSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                alignment: Alignment.center,
                child: Text(cat.emoji, style: const TextStyle(fontSize: 26)),
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
                      '${cat.label} · ${village.memberCount}/${village.maxMembers}명',
                      style:
                          AppTheme.body(size: 12, color: AppTheme.textSub),
                    ),
                    if (village.description != null &&
                        village.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        village.description!,
                        style: AppTheme.body(
                            size: 13, color: AppTheme.textSub),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _joinButton(village),
            ],
          ),
        ),
      ),
    );
  }

  Widget _joinButton(Village village) {
    if (village.isJoined) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Text(
          '가입됨',
          style: AppTheme.body(
            size: 12,
            color: AppTheme.textLight,
            weight: FontWeight.w600,
          ),
        ),
      );
    }

    if (village.isFull) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Text(
          '정원 마감',
          style: AppTheme.body(
            size: 12,
            color: AppTheme.textLight,
            weight: FontWeight.w600,
          ),
        ),
      );
    }

    final joining = _joining.contains(village.id);
    return GestureDetector(
      onTap: joining ? null : () => _join(village),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: joining
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.textOnPrimary,
                ),
              )
            : Text(
                '가입',
                style: AppTheme.body(
                  size: 12,
                  color: AppTheme.textOnPrimary,
                  weight: FontWeight.w700,
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
          const Text('🏡', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            _search.isEmpty && _selectedCategory == null
                ? '아직 마을이 없어요\n첫 번째 마을을 만들어 보세요!'
                : '조건에 맞는 마을이 없어요\n다른 키워드로 검색해 보세요',
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