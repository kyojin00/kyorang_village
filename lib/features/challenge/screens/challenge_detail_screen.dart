import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/challenge.dart';
import '../services/challenge_service.dart';
import '../widgets/challenge_progress_grid.dart';

/// 챌린지 상세 화면 (진행 그리드 + 인증 피드)
class ChallengeDetailScreen extends ConsumerStatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challenge});

  final Challenge challenge;

  @override
  ConsumerState<ChallengeDetailScreen> createState() =>
      _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState
    extends ConsumerState<ChallengeDetailScreen> {
  late Challenge _challenge;
  List<ChallengeCheckin> _checkins = [];
  bool _loadingCheckins = true;
  bool _busy = false;

  String get _myId => AuthService.instance.currentUserId ?? '';
  bool get _isCreator => _challenge.creatorId == _myId;

  /// 본인이 인증한 날짜 집합 (그리드용)
  Set<DateTime> get _myCheckedDates {
    return _checkins
        .where((c) => c.userId == _myId)
        .map((c) => DateTime(
              c.checkinDate.year,
              c.checkinDate.month,
              c.checkinDate.day,
            ))
        .toSet();
  }

  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    _reload();
  }

  Future<void> _reload() async {
    try {
      final service = ref.read(challengeServiceProvider);
      final results = await Future.wait([
        service.fetchChallenge(_challenge.id),
        service.fetchCheckins(_challenge.id),
      ]);
      if (!mounted) return;
      setState(() {
        _challenge = results[0] as Challenge;
        _checkins = results[1] as List<ChallengeCheckin>;
        _loadingCheckins = false;
      });
    } catch (e) {
      print('[CHALLENGE_DETAIL] 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loadingCheckins = false);
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(challengeServiceProvider).joinChallenge(_challenge.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _challenge = _challenge.copyWith(
          isParticipating: true,
          participantCount: _challenge.participantCount + 1,
        );
      });
      _snack('챌린지에 참가했어요!');
    } catch (e) {
      print('[CHALLENGE_DETAIL] 참가 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('참가하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _openCheckinSheet() async {
    final input = await showModalBottomSheet<_CheckinInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (_) => const _CheckinSheet(),
    );
    if (input == null || !mounted) return;
    await _submitCheckin(input);
  }

  Future<void> _submitCheckin(_CheckinInput input) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      String? imageUrl;
      if (input.image != null) {
        imageUrl = await ref.read(storageServiceProvider).uploadImage(
              bucket: StorageBuckets.checkins,
              file: input.image!,
            );
      }

      final checkin = await ref.read(challengeServiceProvider).addCheckin(
            challengeId: _challenge.id,
            content: input.text.isEmpty ? null : input.text,
            imageUrl: imageUrl,
          );

      if (!mounted) return;
      if (checkin == null) {
        setState(() {
          _busy = false;
          _challenge = _challenge.copyWith(hasCheckedInToday: true);
        });
        _snack('오늘은 이미 인증을 완료했어요.');
        return;
      }

      setState(() {
        _busy = false;
        _checkins.insert(0, checkin);
        _challenge = _challenge.copyWith(
          hasCheckedInToday: true,
          myCheckinCount: _challenge.myCheckinCount + 1,
        );
      });
      _snack('오늘 인증 완료! 잘하고 있어요.');
    } catch (e) {
      print('[CHALLENGE_DETAIL] 인증 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('인증을 올리지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _deleteCheckin(ChallengeCheckin checkin) async {
    final ok = await _confirm(
      title: '인증 삭제',
      message: '이 인증을 삭제할까요?',
    );
    if (ok != true) return;

    try {
      await ref.read(challengeServiceProvider).deleteCheckin(checkin.id);
      if (checkin.imageUrl != null) {
        await StorageService.instance.deleteByUrl(
          bucket: StorageBuckets.checkins,
          url: checkin.imageUrl!,
        );
      }
      if (!mounted) return;

      final today = DateTime.now();
      final wasToday = checkin.checkinDate.year == today.year &&
          checkin.checkinDate.month == today.month &&
          checkin.checkinDate.day == today.day;

      setState(() {
        _checkins.removeWhere((c) => c.id == checkin.id);
        _challenge = _challenge.copyWith(
          myCheckinCount: _challenge.myCheckinCount - 1,
          hasCheckedInToday: wasToday ? false : null,
        );
      });
    } catch (e) {
      print('[CHALLENGE_DETAIL] 인증 삭제 실패: $e');
      if (!mounted) return;
      _snack('인증을 삭제하지 못했어요.');
    }
  }

  Future<void> _leave() async {
    final ok = await _confirm(
      title: '참가 취소',
      message: '챌린지 참가를 취소할까요?\n지금까지의 인증 기록은 남아 있어요.',
    );
    if (ok != true || _busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(challengeServiceProvider).leaveChallenge(_challenge.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _challenge = _challenge.copyWith(
          isParticipating: false,
          participantCount: _challenge.participantCount - 1,
        );
      });
    } catch (e) {
      print('[CHALLENGE_DETAIL] 참가 취소 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('참가를 취소하지 못했어요.');
    }
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      title: '챌린지 삭제',
      message: '이 챌린지를 삭제할까요?\n모든 인증 기록이 함께 사라져요.',
    );
    if (ok != true || _busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(challengeServiceProvider).deleteChallenge(_challenge.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      print('[CHALLENGE_DETAIL] 삭제 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('삭제하지 못했어요.');
    }
  }

  Future<bool?> _confirm({required String title, required String message}) {
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
              '확인',
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
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        title: const Text('챌린지'),
        actions: [
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
              if (_challenge.isParticipating && !_isCreator)
                PopupMenuItem(
                  value: 'leave',
                  child: Text('참가 취소',
                      style: AppTheme.body(size: 14, color: AppTheme.error)),
                ),
              if (_isCreator)
                PopupMenuItem(
                  value: 'delete',
                  child: Text('챌린지 삭제',
                      style: AppTheme.body(size: 14, color: AppTheme.error)),
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
              _headerCard(),
              const SizedBox(height: 16),
              _actionArea(),
              const SizedBox(height: 24),
              Text('인증 피드', style: AppTheme.display(size: 20)),
              const SizedBox(height: 12),
              if (_loadingCheckins)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_checkins.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '아직 인증이 없어요\n첫 인증의 주인공이 되어 보세요!',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(
                        size: 13,
                        color: AppTheme.textLight,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              else
                ..._checkins.map(_checkinCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    final status = _challenge.status;
    final statusColor = switch (status) {
      ChallengeStatus.active => AppTheme.secondary,
      ChallengeStatus.upcoming => AppTheme.accent,
      ChallengeStatus.ended => AppTheme.textLight,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                  _challenge.periodLabel,
                  style: AppTheme.body(size: 12, color: AppTheme.textSub),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_challenge.title, style: AppTheme.display(size: 24)),
            if (_challenge.description != null &&
                _challenge.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _challenge.description!,
                style: AppTheme.body(
                  size: 14,
                  color: AppTheme.textSub,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.people_alt_rounded,
                    size: 16, color: AppTheme.secondary),
                const SizedBox(width: 4),
                Text(
                  '${_challenge.participantCount}명 도전 중',
                  style: AppTheme.body(
                    size: 13,
                    color: AppTheme.secondaryDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            // ---- 진행 그리드 (참가자만 표시) ----
            if (_challenge.isParticipating) ...[
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 16),
              ChallengeProgressGrid(
                challenge: _challenge,
                myCheckedDates: _myCheckedDates,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionArea() {
    final status = _challenge.status;

    if (!_challenge.isParticipating) {
      if (status == ChallengeStatus.ended) {
        return const SizedBox.shrink();
      }
      return ElevatedButton(
        onPressed: _busy ? null : _join,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.textOnPrimary,
                ),
              )
            : const Text('챌린지 참가하기'),
      );
    }

    return switch (status) {
      ChallengeStatus.upcoming => Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.bgSoft,
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          alignment: Alignment.center,
          child: Text(
            '${_challenge.startDate.month}.${_challenge.startDate.day}부터 인증할 수 있어요',
            style: AppTheme.body(size: 13, color: AppTheme.textSub),
          ),
        ),
      ChallengeStatus.ended => Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.bgSoft,
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          alignment: Alignment.center,
          child: Text(
            '챌린지가 종료됐어요. 수고했어요!',
            style: AppTheme.body(size: 13, color: AppTheme.textSub),
          ),
        ),
      ChallengeStatus.active => _challenge.hasCheckedInToday
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: AppTheme.secondaryDark),
                  const SizedBox(width: 6),
                  Text(
                    '오늘 인증 완료',
                    style: AppTheme.body(
                      size: 14,
                      color: AppTheme.secondaryDark,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          : ElevatedButton(
              onPressed: _busy ? null : _openCheckinSheet,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.textOnPrimary,
                      ),
                    )
                  : const Text('오늘 인증하기'),
            ),
    };
  }

  Widget _checkinCard(ChallengeCheckin checkin) {
    final mine = checkin.userId == _myId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.bgSoft,
                    backgroundImage: checkin.userAvatarUrl != null
                        ? CachedNetworkImageProvider(checkin.userAvatarUrl!)
                        : null,
                    child: checkin.userAvatarUrl == null
                        ? Text(
                            checkin.userNickname.characters.first,
                            style: AppTheme.body(
                              size: 11,
                              weight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    checkin.userNickname,
                    style: AppTheme.body(size: 13, weight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${checkin.dateLabel} 인증',
                    style:
                        AppTheme.body(size: 11, color: AppTheme.textLight),
                  ),
                  const Spacer(),
                  if (mine)
                    GestureDetector(
                      onTap: () => _deleteCheckin(checkin),
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: AppTheme.textLight),
                    ),
                ],
              ),
              if (checkin.imageUrl != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  child: CachedNetworkImage(
                    imageUrl: checkin.imageUrl!,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 180,
                      color: AppTheme.bgSoft,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 100,
                      color: AppTheme.bgSoft,
                      child: const Center(
                        child: Icon(Icons.broken_image_rounded,
                            color: AppTheme.textLight),
                      ),
                    ),
                  ),
                ),
              ],
              if (checkin.content != null &&
                  checkin.content!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  checkin.content!,
                  style: AppTheme.body(size: 14, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// 인증 입력 바텀시트
// =============================================================

class _CheckinInput {
  const _CheckinInput({this.image, this.text = ''});

  final XFile? image;
  final String text;
}

class _CheckinSheet extends StatefulWidget {
  const _CheckinSheet();

  @override
  State<_CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends State<_CheckinSheet> {
  final _textController = TextEditingController();
  XFile? _image;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _image != null || _textController.text.trim().isNotEmpty;

  Future<void> _pick(bool camera) async {
    final picked = camera
        ? await StorageService.instance.takePhoto()
        : await StorageService.instance.pickImage();
    if (picked == null || !mounted) return;
    setState(() => _image = picked);
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
              Text('오늘의 인증', style: AppTheme.display(size: 22)),
              const SizedBox(height: 14),
              if (_image != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusM),
                      child: Image.file(
                        File(_image!.path),
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => setState(() => _image = null),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: AppTheme.textMain,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 15, color: AppTheme.bgCard),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side:
                              const BorderSide(color: AppTheme.divider),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusM),
                          ),
                        ),
                        icon: const Icon(Icons.photo_camera_rounded,
                            size: 18),
                        label: const Text('카메라'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side:
                              const BorderSide(color: AppTheme.divider),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusM),
                          ),
                        ),
                        icon: const Icon(Icons.photo_library_rounded,
                            size: 18),
                        label: const Text('갤러리'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                maxLines: 2,
                maxLength: 100,
                style: AppTheme.body(size: 14),
                decoration: const InputDecoration(
                  hintText: '오늘은 어땠나요? (선택)',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _canSubmit
                    ? () => Navigator.of(context).pop(
                          _CheckinInput(
                            image: _image,
                            text: _textController.text.trim(),
                          ),
                        )
                    : null,
                child: const Text('인증 올리기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}