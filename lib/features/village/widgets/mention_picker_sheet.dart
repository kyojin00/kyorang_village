import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/village.dart';

/// 마을 채팅 멘션 멤버 선택 시트
/// 검색 가능한 멤버 목록. 선택하면 해당 멤버 반환.
class MentionPickerSheet extends StatefulWidget {
  const MentionPickerSheet({
    super.key,
    required this.members,
    this.initialQuery = '',
  });

  final List<VillageMember> members;
  final String initialQuery;

  /// 시트 표시 헬퍼. 선택된 멤버 반환, 취소 시 null.
  static Future<VillageMember?> show(
    BuildContext context, {
    required List<VillageMember> members,
    String initialQuery = '',
  }) {
    return showModalBottomSheet<VillageMember>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (_) => MentionPickerSheet(
        members: members,
        initialQuery: initialQuery,
      ),
    );
  }

  @override
  State<MentionPickerSheet> createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends State<MentionPickerSheet> {
  late final TextEditingController _searchController;
  late List<VillageMember> _filtered;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _filtered = _filter(widget.initialQuery);
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    setState(() => _filtered = _filter(_searchController.text));
  }

  List<VillageMember> _filter(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.members;
    return widget.members
        .where((m) => m.nickname.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('멘션할 이웃 선택',
                        style:
                            AppTheme.body(size: 15, weight: FontWeight.w700)),
                    const Spacer(),
                    Text('${widget.members.length}명',
                        style: AppTheme.body(
                            size: 12, color: AppTheme.textLight)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: AppTheme.body(size: 14),
                  decoration: const InputDecoration(
                    hintText: '닉네임 검색',
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AppTheme.textLight, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          '맞는 이웃이 없어요',
                          textAlign: TextAlign.center,
                          style: AppTheme.body(
                              size: 13, color: AppTheme.textLight),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) => _memberTile(_filtered[i]),
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberTile(VillageMember member) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(member),
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.bgSoft,
              backgroundImage: member.avatarUrl != null
                  ? CachedNetworkImageProvider(member.avatarUrl!)
                  : null,
              child: member.avatarUrl == null
                  ? Text(
                      member.nickname.characters.first,
                      style: AppTheme.body(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                member.nickname,
                style: AppTheme.body(size: 14, weight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (member.isOwner)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '마을지기',
                  style: AppTheme.body(
                    size: 10,
                    color: AppTheme.primary,
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