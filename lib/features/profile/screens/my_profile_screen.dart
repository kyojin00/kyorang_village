import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fullscreen_image_viewer.dart';
import '../../village/models/village.dart';
import 'interests_edit_sheet.dart';

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  String _nickname = '';
  String? _bio;
  String? _statusMessage;
  String? _avatarUrl;
  String? _coverUrl;
  List<String> _interests = [];
  bool _loading = true;
  bool _busy = false;

  bool _editing = false;

  String _origNickname = '';
  String? _origBio;
  String? _origStatusMessage;

  late final TextEditingController _nicknameController =
      TextEditingController();
  late final TextEditingController _bioController = TextEditingController();
  late final TextEditingController _statusController =
      TextEditingController();

  String get _myId => AuthService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select(
              'nickname, bio, status_message, avatar_url, cover_url, interests')
          .eq('id', _myId)
          .single();

      if (!mounted) return;
      final interestsRaw = row['interests'];
      final interestsList = <String>[];
      if (interestsRaw is List) {
        for (final v in interestsRaw) {
          if (v is String) interestsList.add(v);
        }
      }

      setState(() {
        _nickname = row['nickname'] as String? ?? '';
        _bio = row['bio'] as String?;
        _statusMessage = row['status_message'] as String?;
        _avatarUrl = row['avatar_url'] as String?;
        _coverUrl = row['cover_url'] as String?;
        _interests = interestsList;
        _loading = false;
      });
    } catch (e) {
      print('[MY_PROFILE] 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _enterEditMode() {
    _origNickname = _nickname;
    _origBio = _bio;
    _origStatusMessage = _statusMessage;

    _nicknameController.text = _nickname;
    _bioController.text = _bio ?? '';
    _statusController.text = _statusMessage ?? '';

    setState(() => _editing = true);
  }

  void _cancelEdit() {
    setState(() {
      _nickname = _origNickname;
      _bio = _origBio;
      _statusMessage = _origStatusMessage;
      _editing = false;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _saveEdit() async {
    final newNickname = _nicknameController.text.trim();
    if (newNickname.length < 2 || newNickname.length > 12) {
      _snack('닉네임은 2~12자로 입력해 주세요.');
      return;
    }

    final newBio = _bioController.text.trim();
    final newStatus = _statusController.text.trim();

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    try {
      await Supabase.instance.client.from('profiles').update({
        'nickname': newNickname,
        'bio': newBio.isEmpty ? null : newBio,
        'status_message': newStatus.isEmpty ? null : newStatus,
      }).eq('id', _myId);

      if (!mounted) return;
      setState(() {
        _nickname = newNickname;
        _bio = newBio.isEmpty ? null : newBio;
        _statusMessage = newStatus.isEmpty ? null : newStatus;
        _editing = false;
        _busy = false;
      });
      _snack('프로필을 저장했어요.');
    } catch (e) {
      print('[MY_PROFILE] 저장 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('저장에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _changeAvatar() async {
    if (_busy) return;
    final picked = await ref.read(storageServiceProvider).pickImage();
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final oldUrl = _avatarUrl;

    try {
      final url = await ref.read(storageServiceProvider).uploadImage(
            bucket: StorageBuckets.avatars,
            file: picked,
          );

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': url}).eq('id', _myId);

      if (oldUrl != null) {
        await StorageService.instance.deleteByUrl(
          bucket: StorageBuckets.avatars,
          url: oldUrl,
        );
      }

      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _busy = false;
      });
      _snack('프로필 사진을 바꿨어요.');
    } catch (e) {
      print('[MY_PROFILE] 아바타 변경 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('사진을 바꾸지 못했어요.');
    }
  }

  Future<void> _changeCover() async {
    if (_busy) return;
    final picked = await ref.read(storageServiceProvider).pickImage();
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final oldUrl = _coverUrl;

    try {
      final url = await ref.read(storageServiceProvider).uploadImage(
            bucket: StorageBuckets.covers,
            file: picked,
          );

      await Supabase.instance.client
          .from('profiles')
          .update({'cover_url': url}).eq('id', _myId);

      if (oldUrl != null) {
        await StorageService.instance.deleteByUrl(
          bucket: StorageBuckets.covers,
          url: oldUrl,
        );
      }

      if (!mounted) return;
      setState(() {
        _coverUrl = url;
        _busy = false;
      });
      _snack('배경 사진을 바꿨어요.');
    } catch (e) {
      print('[MY_PROFILE] 커버 변경 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('배경을 바꾸지 못했어요.');
    }
  }

  Future<void> _removeCover() async {
    if (_busy || _coverUrl == null) return;
    setState(() => _busy = true);
    final oldUrl = _coverUrl;

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'cover_url': null}).eq('id', _myId);

      if (oldUrl != null) {
        await StorageService.instance.deleteByUrl(
          bucket: StorageBuckets.covers,
          url: oldUrl,
        );
      }

      if (!mounted) return;
      setState(() {
        _coverUrl = null;
        _busy = false;
      });
      _snack('배경 사진을 지웠어요.');
    } catch (e) {
      print('[MY_PROFILE] 커버 제거 실패: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('처리하지 못했어요.');
    }
  }

  Future<void> _showCoverMenu() async {
    if (_busy) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: AppTheme.primary),
                title: Text('갤러리에서 사진 선택',
                    style: AppTheme.body(size: 14)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _changeCover();
                },
              ),
              if (_coverUrl != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: AppTheme.error),
                  title: Text('배경 사진 지우기',
                      style:
                          AppTheme.body(size: 14, color: AppTheme.error)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _removeCover();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editInterests() async {
    if (_busy) return;
    final result = await InterestsEditSheet.show(
      context,
      userId: _myId,
      initial: _interests,
    );
    if (result == null || !mounted) return;
    setState(() => _interests = result);
  }

  /// 풀스크린 이미지 뷰어 열기 (URL이 있을 때만)
  void _viewImage(String? url) {
    if (url == null || url.isEmpty) return;
    FullscreenImageViewer.show(context, url);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.bgMain,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final coverHeight = screenHeight * 0.42;
    const avatarRadius = 50.0;
    final avatarTop = coverHeight - avatarRadius;

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildCoverArea(coverHeight),
                SizedBox(height: avatarRadius + 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Column(
                    children: [
                      _buildNickname(),
                      const SizedBox(height: 12),
                      _buildStatus(),
                      const SizedBox(height: 20),
                      _buildBio(),
                      const SizedBox(height: 24),
                      _buildInterests(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 아바타 (전체 화면 Stack 위에)
          Positioned(
            top: avatarTop,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: avatarRadius * 2 + 20,
                height: avatarRadius * 2 + 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 아바타 본체 — 누르면 풀스크린
                    GestureDetector(
                      onTap: _avatarUrl != null
                          ? () => _viewImage(_avatarUrl)
                          : null,
                      child: Container(
                        width: avatarRadius * 2,
                        height: avatarRadius * 2,
                        margin: const EdgeInsets.only(left: 10, top: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.bgMain, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: AppTheme.bgSoft,
                          backgroundImage: _avatarUrl != null
                              ? CachedNetworkImageProvider(_avatarUrl!)
                              : null,
                          child: _avatarUrl == null
                              ? Text(
                                  _nickname.isEmpty
                                      ? '?'
                                      : _nickname.characters.first,
                                  style: AppTheme.body(
                                    size: 36,
                                    weight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    // 카메라 아이콘 — 누르면 사진 변경
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _busy ? null : _changeAvatar,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppTheme.bgMain, width: 2.5),
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded,
              color: Colors.white, size: 20),
        ),
        onPressed: _busy
            ? null
            : (_editing ? _cancelEdit : () => Navigator.of(context).pop()),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: _busy
                ? null
                : (_editing ? _saveEdit : _enterEditMode),
            style: TextButton.styleFrom(
              backgroundColor: _editing
                  ? AppTheme.primary
                  : Colors.black.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusFull),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _editing ? '완료' : '편집',
                    style: AppTheme.body(
                      size: 13,
                      color: Colors.white,
                      weight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverArea(double height) {
    final hasCover = _coverUrl != null && _coverUrl!.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        children: [
          // 배경 — 사진이 있으면 누르면 풀스크린, 없으면 동작 안 함
          GestureDetector(
            onTap: hasCover ? () => _viewImage(_coverUrl) : null,
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: hasCover
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: _coverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            decoration: const BoxDecoration(
                              gradient: AppTheme.warmGradient,
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            decoration: const BoxDecoration(
                              gradient: AppTheme.warmGradient,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.1),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: AppTheme.warmGradient,
                      ),
                    ),
            ),
          ),

          // 배경 카메라 아이콘
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 56,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _busy ? null : _showCoverMenu,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNickname() {
    if (_editing) {
      return TextField(
        controller: _nicknameController,
        textAlign: TextAlign.center,
        maxLength: 12,
        style: AppTheme.display(size: 24),
        decoration: InputDecoration(
          hintText: '닉네임 (2~12자)',
          hintStyle: AppTheme.body(
            size: 18,
            color: AppTheme.textLight,
            weight: FontWeight.w400,
          ),
          counterText: '',
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: AppTheme.primary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        ),
      );
    }
    return Text(_nickname,
        style: AppTheme.display(size: 26),
        textAlign: TextAlign.center);
  }

  Widget _buildStatus() {
    if (_editing) {
      return TextField(
        controller: _statusController,
        textAlign: TextAlign.center,
        maxLength: 30,
        style: AppTheme.body(size: 14),
        decoration: InputDecoration(
          hintText: '오늘 기분이나 지금 상황을 한 줄로',
          hintStyle: AppTheme.body(
            size: 13,
            color: AppTheme.textLight,
          ),
          counterText: '',
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: AppTheme.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        ),
      );
    }
    if (_statusMessage == null || _statusMessage!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        '"${_statusMessage!}"',
        style: AppTheme.body(
          size: 14,
          color: AppTheme.primaryDark,
          weight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBio() {
    if (_editing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: TextField(
          controller: _bioController,
          maxLines: 5,
          minLines: 3,
          maxLength: 200,
          style: AppTheme.body(size: 14, height: 1.5),
          decoration: InputDecoration(
            hintText: '자기소개 (선택)',
            hintStyle:
                AppTheme.body(size: 14, color: AppTheme.textLight),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            counterText: '',
          ),
        ),
      );
    }
    if (_bio == null || _bio!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Text(
        _bio!,
        textAlign: TextAlign.left,
        style: AppTheme.body(
          size: 14,
          color: AppTheme.textMain,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildInterests() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '관심사',
              style: AppTheme.body(
                size: 13,
                color: AppTheme.textLight,
                weight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_editing)
              TextButton(
                onPressed: _busy ? null : _editInterests,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _interests.isEmpty ? '추가' : '편집',
                  style: AppTheme.body(
                    size: 12,
                    color: AppTheme.primary,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_interests.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.bgSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            child: Text(
              '관심사를 추가하면 비슷한 이웃을 찾기 쉬워져요',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 13,
                color: AppTheme.textLight,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _interests.map((code) {
              final cat = VillageCategory.fromCode(code);
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bgSoft,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusFull),
                  border:
                      Border.all(color: AppTheme.divider, width: 1),
                ),
                child: Text(
                  '${cat.emoji} ${cat.label}',
                  style: AppTheme.body(
                      size: 13, weight: FontWeight.w600),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}