import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/safety_service.dart';
import '../../../core/theme/app_theme.dart';

/// 차단 관리 화면
/// 마이 탭에서 진입. 차단한 이웃 목록 + 각 항목별 차단 해제.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() =>
      _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<BlockedProfile> _items = [];
  bool _loading = true;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      // 캐시 우회 위해 refresh 한 번
      await SafetyService.instance.fetchBlockedIds(refresh: true);
      final list = await SafetyService.instance.fetchBlockedProfiles();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      print('[BLOCKED] 조회 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _unblock(BlockedProfile p) async {
    if (_processing.contains(p.userId)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('차단 해제',
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          '${p.nickname}님의 차단을 해제할까요?\n'
          '이 사람의 채팅·게시글·댓글이 다시 보이게 돼요.',
          style:
              AppTheme.body(size: 14, color: AppTheme.textSub, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: AppTheme.body(size: 14, color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '차단 해제',
              style: AppTheme.body(
                size: 14,
                color: AppTheme.primary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _processing.add(p.userId));
    try {
      await SafetyService.instance.unblock(p.userId);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((x) => x.userId == p.userId);
        _processing.remove(p.userId);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('${p.nickname}님의 차단을 해제했어요.')));
    } catch (e) {
      print('[BLOCKED] 해제 실패: $e');
      if (!mounted) return;
      setState(() => _processing.remove(p.userId));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('차단 해제에 실패했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: const Text('차단한 이웃')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? _emptyView()
                : RefreshIndicator(
                    onRefresh: _fetch,
                    color: AppTheme.primary,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: _items.length,
                      itemBuilder: (context, i) => _row(_items[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _row(BlockedProfile p) {
    final processing = _processing.contains(p.userId);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.bgSoft,
            backgroundImage: p.avatarUrl != null
                ? CachedNetworkImageProvider(p.avatarUrl!)
                : null,
            child: p.avatarUrl == null
                ? Text(
                    p.nickname.characters.first,
                    style: AppTheme.body(
                      size: 16,
                      weight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nickname,
                  style: AppTheme.body(size: 15, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDate(p.blockedAt)} 차단',
                  style:
                      AppTheme.body(size: 11, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
          if (processing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            OutlinedButton(
              onPressed: () => _unblock(p),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.divider),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusFull),
                ),
              ),
              child: Text(
                '차단 해제',
                style: AppTheme.body(
                  size: 12,
                  color: AppTheme.primary,
                  weight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          '차단한 이웃이 없어요',
          style: AppTheme.body(size: 14, color: AppTheme.textSub),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }
}