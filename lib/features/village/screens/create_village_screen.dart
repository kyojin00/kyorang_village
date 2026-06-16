import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/village.dart';
import '../services/village_service.dart';

/// 마을 만들기 화면
/// 생성 성공 시 생성된 Village를 pop 결과로 반환한다.
class CreateVillageScreen extends ConsumerStatefulWidget {
  const CreateVillageScreen({super.key});

  @override
  ConsumerState<CreateVillageScreen> createState() =>
      _CreateVillageScreenState();
}

class _CreateVillageScreenState extends ConsumerState<CreateVillageScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  String? _selectedCategory;
  int _maxMembers = 100;
  bool _loading = false;

  static const List<int> _maxMemberOptions = [20, 50, 100, 300];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().length >= 2 &&
      _selectedCategory != null &&
      !_loading;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final village = await ref.read(villageServiceProvider).createVillage(
            name: _nameController.text,
            category: _selectedCategory!,
            description: _descController.text.trim().isEmpty
                ? null
                : _descController.text,
            maxMembers: _maxMembers,
          );

      // 내 마을 목록 갱신
      ref.invalidate(myVillagesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${village.name} 마을이 생겼어요!')),
      );
      Navigator.of(context).pop(village);
    } catch (e) {
      print('[VILLAGE] 생성 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마을을 만들지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: const Text('마을 만들기')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('어떤 마을인가요?', style: AppTheme.display(size: 24)),
              const SizedBox(height: 20),

              // ---- 마을 이름 ----
              _label('마을 이름'),
              TextField(
                controller: _nameController,
                maxLength: 20,
                style: AppTheme.body(size: 15, weight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '예: 아침 6시 기상 마을',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              // ---- 카테고리 ----
              _label('카테고리'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VillageCategory.all.map((c) {
                  final selected = _selectedCategory == c.code;
                  return ChoiceChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = c.code),
                    labelStyle: AppTheme.body(
                      size: 13,
                      color: selected
                          ? AppTheme.textOnPrimary
                          : AppTheme.textSub,
                      weight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // ---- 소개 ----
              _label('마을 소개 (선택)'),
              TextField(
                controller: _descController,
                maxLines: 3,
                maxLength: 100,
                style: AppTheme.body(size: 14),
                decoration: const InputDecoration(
                  hintText: '우리 마을은 어떤 곳인지 알려 주세요',
                ),
              ),
              const SizedBox(height: 12),

              // ---- 최대 인원 ----
              _label('최대 인원'),
              Wrap(
                spacing: 8,
                children: _maxMemberOptions.map((n) {
                  final selected = _maxMembers == n;
                  return ChoiceChip(
                    label: Text('$n명'),
                    selected: selected,
                    onSelected: (_) => setState(() => _maxMembers = n),
                    labelStyle: AppTheme.body(
                      size: 13,
                      color: selected
                          ? AppTheme.textOnPrimary
                          : AppTheme.textSub,
                      weight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // ---- 생성 버튼 ----
              ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.textOnPrimary,
                        ),
                      )
                    : const Text('마을 만들기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTheme.body(
          size: 13,
          color: AppTheme.textSub,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}