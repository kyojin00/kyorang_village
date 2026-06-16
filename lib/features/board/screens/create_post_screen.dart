import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../services/board_service.dart';

/// 글쓰기 화면
/// 작성 성공 시 생성된 Post를 pop 결과로 반환한다.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, required this.villageId});

  final String villageId;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _contentController = TextEditingController();
  final List<XFile> _images = [];

  bool _submitting = false;

  static const int _maxImages = 4;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _contentController.text.trim().isNotEmpty && !_submitting;

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _pickImages() async {
    if (_images.length >= _maxImages) {
      _snack('사진은 최대 $_maxImages장까지 첨부할 수 있어요.');
      return;
    }
    final picked = await ref
        .read(storageServiceProvider)
        .pickImages(limit: _maxImages - _images.length);
    if (picked.isEmpty || !mounted) return;
    setState(() => _images.addAll(picked));
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      // 1. 이미지 업로드
      List<String> imageUrls = const [];
      if (_images.isNotEmpty) {
        imageUrls = await ref.read(storageServiceProvider).uploadImages(
              bucket: StorageBuckets.posts,
              files: _images,
            );
      }

      // 2. 글 저장
      final post = await ref.read(boardServiceProvider).createPost(
            villageId: widget.villageId,
            content: _contentController.text,
            imageUrls: imageUrls,
          );

      if (!mounted) return;
      Navigator.of(context).pop(post);
    } catch (e) {
      print('[CREATE_POST] 작성 실패: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('글을 올리지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
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
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        title: const Text('글쓰기'),
        actions: [
          TextButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(
                    '올리기',
                    style: AppTheme.body(
                      size: 15,
                      weight: FontWeight.w700,
                      color: _canSubmit
                          ? AppTheme.primary
                          : AppTheme.textLight,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _contentController,
                      minLines: 6,
                      maxLines: 12,
                      maxLength: 1000,
                      autofocus: true,
                      style: AppTheme.body(size: 15, height: 1.6),
                      decoration: const InputDecoration(
                        hintText: '이웃들과 나누고 싶은 이야기를 적어 보세요',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_images.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _imagePreviews(),
                    ],
                  ],
                ),
              ),
            ),

            // ---- 하단 도구 바 ----
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.bgCard,
                border: Border(
                  top: BorderSide(color: AppTheme.divider, width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _submitting ? null : _pickImages,
                    icon: const Icon(
                      Icons.photo_library_rounded,
                      color: AppTheme.primary,
                    ),
                  ),
                  Text(
                    '${_images.length}/$_maxImages',
                    style:
                        AppTheme.body(size: 12, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePreviews() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                child: Image.file(
                  File(_images[i].path),
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _submitting ? null : () => _removeImage(i),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppTheme.textMain,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppTheme.bgCard,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}