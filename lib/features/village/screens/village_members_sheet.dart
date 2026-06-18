import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../friend/widgets/profile_sheet.dart';
import '../models/village.dart';
import '../services/village_service.dart';

/// 마을 멤버 목록 바텀시트
///
/// 정렬:
///   1. 촌장 항상 맨 위
///   2. 나머지는 가입일 빠른 순 (오래된 이웃 먼저)
///
/// 표시:
///   - 가입일 라벨 ("3일 전 가입", "오늘 가입")
///   - 본인은 "나" 칩
///   - 촌장은 "촌장" 칩
class VillageMembersSheet extends ConsumerStatefulWidget {
  const VillageMembersSheet({super.key, required this.villageId});

  final String villageId;

  static Future<void> show(
    BuildContext context, {
    required String villageId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (_) => VillageMembersSheet(villageId: villageId),
    );
  }

  @override
  ConsumerState<VillageMembersSheet> createState() =>
      _VillageMembersSheetState();
}

class _VillageMembersSheetState
    extends ConsumerState<VillageMembersSheet> {
  List<VillageMember> _members = [];
  bool _loading = true;

  String get _myId => AuthService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list =
          await VillageService.instance.fetchMembers(widget.villageId);

      // 정렬: 촌장 먼저 → 가입일 오름차순 (오래된 이웃 먼저)
      list.sort((a, b) {
        if (a.isOwner && !b.isOwner) return -1;
        if (!a.isOwner && b.isOwner) return 1;
        return a.joinedAt.compareTo(b.joinedAt);
      });

      if (!mounted) return;
      setState(() {
        _members = list;
        _loading = false;
      });
    } catch (e) {
      print('[MEMBERS_SHEET] 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _joinLabel(DateTime joinedAt) {
    final now = DateTime.now();
    final diff = now.difference(joinedAt);

    if (diff.inDays == 0) return '오늘 가입';
    if (diff.inDays == 1) return '어제 가입';
    if (diff.inDays < 7) return '${diff.inDays}일 전 가입';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}주 전 가입';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}달 전 가입';
    return '${(diff.inDays / 365).floor()}년 전 가입';
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 핸들
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('마을 이웃', style: AppTheme.display(size: 22)),
                  const SizedBox(width: 8),
                  if (!_loading)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSoft,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        '${_members.length}명',
                        style: AppTheme.body(
                          size: 11,
                          color: AppTheme.textSub,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                            child: CircularProgressIndicator()),
                      )
                    : _members.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '아직 이웃이 없어요.',
                              style: AppTheme.body(
                                  size: 14, color: AppTheme.textSub),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _members.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, i) =>
                                _memberRow(_members[i]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberRow(VillageMember m) {
    final isMe = m.userId == _myId;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      onTap: () => ProfileSheet.show(
        context,
        userId: m.userId,
        nickname: m.nickname,
        avatarUrl: m.avatarUrl,
      ),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? AppTheme.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.bgSoft,
              backgroundImage: m.avatarUrl != null
                  ? NetworkImage(m.avatarUrl!)
                  : null,
              child: m.avatarUrl == null
                  ? Text(
                      m.nickname.characters.first,
                      style: AppTheme.body(
                        size: 15,
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.nickname,
                          style: AppTheme.body(
                              size: 14, weight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull),
                          ),
                          child: Text(
                            '나',
                            style: AppTheme.body(
                              size: 10,
                              color: Colors.white,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _joinLabel(m.joinedAt),
                    style: AppTheme.body(
                        size: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
            if (m.isOwner)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bgSoft,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '촌장',
                  style: AppTheme.body(
                    size: 11,
                    color: AppTheme.primaryDark,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}