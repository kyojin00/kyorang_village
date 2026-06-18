import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../board/screens/board_screen.dart';
import '../../challenge/screens/challenge_list_screen.dart';
import '../models/village.dart';
import '../services/village_service.dart';
import 'village_chat_screen.dart';
import 'village_members_sheet.dart';

/// 마을 상세 화면
/// 채팅 / 게시판 / 챌린지로 들어가는 마을의 현관이다.
/// 미가입 마을이면 기능 메뉴 대신 가입 버튼을 보여준다.
class VillageDetailScreen extends ConsumerStatefulWidget {
  const VillageDetailScreen({super.key, required this.village});

  final Village village;

  @override
  ConsumerState<VillageDetailScreen> createState() =>
      _VillageDetailScreenState();
}

class _VillageDetailScreenState extends ConsumerState<VillageDetailScreen> {
  late Village _village;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _village = widget.village;
    _reload();
  }

  bool get _isOwner =>
      _village.ownerId == AuthService.instance.currentUserId;

  Future<void> _reload() async {
    try {
      final fresh =
          await ref.read(villageServiceProvider).fetchVillage(_village.id);
      if (!mounted) return;
      setState(() => _village = fresh);
    } catch (e) {
      print('[VILLAGE_DETAIL] 갱신 실패: $e');
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(villageServiceProvider).joinVillage(_village.id);
      ref.invalidate(myVillagesProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _village = _village.copyWith(
          isJoined: true,
          memberCount: _village.memberCount + 1,
        );
      });
      _snack('${_village.name} 마을에 가입했어요!');
    } catch (e) {
      print('[VILLAGE_DETAIL] 가입 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('가입하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VillageChatScreen(village: _village),
      ),
    );
  }

  Future<void> _showMembers() async {
    VillageMembersSheet.show(context, villageId: _village.id);
  }

  Future<void> _leave() async {
    final ok = await _confirm(
      title: '마을 탈퇴',
      message: '${_village.name} 마을에서 나갈까요?',
      confirmLabel: '탈퇴',
    );
    if (ok != true || _busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(villageServiceProvider).leaveVillage(_village.id);
      ref.invalidate(myVillagesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      print('[VILLAGE_DETAIL] 탈퇴 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('탈퇴하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      title: '마을 삭제',
      message:
          '${_village.name} 마을을 삭제할까요?\n모든 대화와 게시글이 함께 사라지고 되돌릴 수 없어요.',
      confirmLabel: '삭제',
    );
    if (ok != true || _busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(villageServiceProvider).deleteVillage(_village.id);
      ref.invalidate(myVillagesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      print('[VILLAGE_DETAIL] 삭제 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text(title,
            style: AppTheme.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          message,
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
              confirmLabel,
              style: AppTheme.body(
                size: 14,
                color: AppTheme.error,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cat = _village.categoryInfo;

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        title: Text(_village.name),
        actions: [
          if (_village.isJoined)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              color: AppTheme.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
              ),
              onSelected: (value) {
                if (value == 'leave') _leave();
                if (value == 'delete') _delete();
              },
              itemBuilder: (_) => [
                if (!_isOwner)
                  PopupMenuItem(
                    value: 'leave',
                    child: Text('마을 탈퇴',
                        style:
                            AppTheme.body(size: 14, color: AppTheme.error)),
                  ),
                if (_isOwner)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('마을 삭제',
                        style:
                            AppTheme.body(size: 14, color: AppTheme.error)),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          color: AppTheme.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: AppTheme.warmGradient,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusM),
                            ),
                            alignment: Alignment.center,
                            child: Text(cat.emoji,
                                style: const TextStyle(fontSize: 28)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_village.name,
                                    style: AppTheme.display(size: 22)),
                                const SizedBox(height: 2),
                                Text(
                                  cat.label,
                                  style: AppTheme.body(
                                      size: 12, color: AppTheme.textSub),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_village.description != null &&
                          _village.description!.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          _village.description!,
                          style: AppTheme.body(
                            size: 14,
                            color: AppTheme.textSub,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: _showMembers,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusS),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.people_alt_rounded,
                                  size: 18, color: AppTheme.secondary),
                              const SizedBox(width: 6),
                              Text(
                                '이웃 ${_village.memberCount}명',
                                style: AppTheme.body(
                                  size: 13,
                                  color: AppTheme.secondaryDark,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 18, color: AppTheme.textLight),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_village.isJoined) ...[
                _menuTile(
                  icon: Icons.chat_bubble_rounded,
                  title: '마을 채팅',
                  subtitle: '이웃들과 실시간으로 이야기해요',
                  onTap: _openChat,
                ),
                const SizedBox(height: 12),
                _menuTile(
                  icon: Icons.article_rounded,
                  title: '게시판',
                  subtitle: '글과 사진으로 소식을 나눠요',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BoardScreen(village: _village),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _menuTile(
                  icon: Icons.flag_rounded,
                  title: '챌린지',
                  subtitle: '함께 목표를 세우고 인증해요',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ChallengeListScreen(village: _village),
                    ),
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '마을에 가입하면 채팅, 게시판, 챌린지에\n참여할 수 있어요.',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(
                      size: 13,
                      color: AppTheme.textSub,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed:
                      (_village.isFull || _busy) ? null : _join,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.textOnPrimary,
                          ),
                        )
                      : Text(_village.isFull ? '정원 마감' : '마을 가입하기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.bgSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Icon(icon, size: 22, color: AppTheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            AppTheme.body(size: 15, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          AppTheme.body(size: 12, color: AppTheme.textSub),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textLight),
            ],
          ),
        ),
      ),
    );
  }
}