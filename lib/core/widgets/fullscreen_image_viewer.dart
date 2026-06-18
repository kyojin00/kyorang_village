import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';

/// 전체화면 이미지 뷰어
/// 핀치 줌 + 다운로드 + 공유
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
  });

  final String imageUrl;

  static Future<void> show(BuildContext context, String url) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => FullscreenImageViewer(imageUrl: url),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() =>
      _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  bool _saving = false;
  bool _sharing = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 이미지를 임시 파일로 다운로드
  Future<File?> _downloadToTemp() async {
    try {
      final res = await http.get(Uri.parse(widget.imageUrl));
      if (res.statusCode != 200) return null;

      final dir = await getTemporaryDirectory();
      final fileName =
          'kyorang_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(res.bodyBytes);
      return file;
    } catch (e) {
      print('[VIEWER] 다운로드 실패: $e');
      return null;
    }
  }

  /// 갤러리에 저장
  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // 권한 확인 (Android 13+)
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (!mounted) return;
          _snack('사진 저장 권한이 필요해요.');
          return;
        }
      }

      // 임시 파일로 받기
      final file = await _downloadToTemp();
      if (file == null) {
        if (!mounted) return;
        _snack('이미지를 받지 못했어요.');
        return;
      }

      // 갤러리에 저장
      await Gal.putImage(file.path, album: '교랑빌리지');

      if (!mounted) return;
      _snack('사진을 저장했어요.');
    } on GalException catch (e) {
      print('[VIEWER] 갤러리 저장 실패: ${e.type}');
      if (!mounted) return;
      _snack('사진을 저장하지 못했어요.');
    } catch (e) {
      print('[VIEWER] 저장 예외: $e');
      if (!mounted) return;
      _snack('사진을 저장하지 못했어요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 시스템 공유 시트
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final file = await _downloadToTemp();
      if (file == null) {
        if (!mounted) return;
        _snack('이미지를 받지 못했어요.');
        return;
      }

      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      print('[VIEWER] 공유 실패: $e');
      if (!mounted) return;
      _snack('공유하지 못했어요.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 배경 탭 시 닫기
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
          // 이미지
          Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
          // 상단 닫기 버튼
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          // 하단 액션 바 (저장 + 공유)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionButton(
                      icon: Icons.download_rounded,
                      label: '저장',
                      busy: _saving,
                      onTap: _saveToGallery,
                    ),
                    _actionButton(
                      icon: Icons.share_rounded,
                      label: '공유',
                      busy: _sharing,
                      onTap: _share,
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

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}