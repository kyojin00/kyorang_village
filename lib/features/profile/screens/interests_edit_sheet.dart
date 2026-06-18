import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../village/models/village.dart';

/// 관심사 편집 시트
/// VillageCategory를 그대로 재활용 — 마을 카테고리와 같은 관심사 체계
class InterestsEditSheet extends StatefulWidget {
  const InterestsEditSheet({
    super.key,
    required this.userId,
    required this.initial,
  });

  final String userId;
  final List<String> initial;

  /// 시트 표시 헬퍼. 저장한 새 관심사 목록 반환, 취소 시 null.
  static Future<List<String>?> show(
    BuildContext context, {
    required String userId,
    required List<String> initial,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (_) => InterestsEditSheet(userId: userId, initial: initial),
    );
  }

  @override
  State<InterestsEditSheet> createState() => _InterestsEditSheetState();
}

class _InterestsEditSheetState extends State<InterestsEditSheet> {
  late final Set<String> _selected;
  bool _saving = false;

  /// 한 번에 선택할 수 있는 최대 관심사 개수
  static const int _maxSelectable = 5;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.toSet();
  }

  void _toggle(String code) {
    setState(() {
      if (_selected.contains(code)) {
        _selected.remove(code);
      } else {
        if (_selected.length >= _maxSelectable) return;
        _selected.add(code);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await Supabase.instance.client.from('profiles').update({
        'interests': _selected.toList(),
      }).eq('id', widget.userId);

      if (!mounted) return;
      Navigator.of(context).pop(_selected.toList());
    } catch (e) {
      print('[INTERESTS] 저장 실패: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('저장하지 못했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                  Text(
                    '관심사 선택',
                    style: AppTheme.body(size: 18, weight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    '${_selected.length} / $_maxSelectable',
                    style: AppTheme.body(
                        size: 12, color: AppTheme.textLight),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '관심 있는 분야를 최대 ${_maxSelectable}개까지 선택해 주세요',
                style: AppTheme.body(
                    size: 12, color: AppTheme.textLight, height: 1.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VillageCategory.all.map(_chip).toList(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(VillageCategory cat) {
    final selected = _selected.contains(cat.code);
    final atLimit = !selected && _selected.length >= _maxSelectable;
    return FilterChip(
      label: Text('${cat.emoji} ${cat.label}'),
      selected: selected,
      onSelected: atLimit ? null : (_) => _toggle(cat.code),
      labelStyle: AppTheme.body(
        size: 13,
        color: selected
            ? AppTheme.textOnPrimary
            : (atLimit ? AppTheme.textLight : AppTheme.textSub),
        weight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.bgSoft,
      checkmarkColor: AppTheme.textOnPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        side: BorderSide(
          color: selected ? AppTheme.primary : AppTheme.divider,
          width: 1,
        ),
      ),
    );
  }
}