import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Supabase Storage 업로드 공용 헬퍼
///
/// 버킷: avatars / villages / posts / checkins / chat-images
/// 경로 규칙: {uid}/{uuid}.jpg
/// (Storage RLS가 첫 번째 폴더명 == 본인 uid 일 때만 업로드를 허용한다)
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  static const _uuid = Uuid();

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  // ===========================================================
  // 이미지 선택
  // ===========================================================

  /// 갤러리에서 이미지 1장 선택 (자동 리사이즈/압축)
  /// 저사양 기기 대응: 긴 변 1280px, 품질 80으로 picker 단계에서 줄인다.
  Future<XFile?> pickImage() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
  }

  /// 갤러리에서 여러 장 선택 (최대 [limit]장)
  Future<List<XFile>> pickImages({int limit = 4}) async {
    final files = await _picker.pickMultiImage(
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    return files.take(limit).toList();
  }

  /// 카메라 촬영 (챌린지 인증용)
  Future<XFile?> takePhoto() {
    return _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
  }

  // ===========================================================
  // 업로드
  // ===========================================================

  /// 이미지 1장 업로드 후 public URL 반환
  Future<String> uploadImage({
    required String bucket,
    required XFile file,
  }) async {
    final path = '$_uid/${_uuid.v4()}.jpg';

    await _supabase.storage.from(bucket).upload(
          path,
          File(file.path),
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    final url = _supabase.storage.from(bucket).getPublicUrl(path);
    print('[STORAGE] 업로드 완료: $bucket/$path');
    return url;
  }

  /// 여러 장 순차 업로드 (하나라도 실패하면 예외)
  Future<List<String>> uploadImages({
    required String bucket,
    required List<XFile> files,
  }) async {
    final urls = <String>[];
    for (final file in files) {
      urls.add(await uploadImage(bucket: bucket, file: file));
    }
    return urls;
  }

  // ===========================================================
  // 삭제
  // ===========================================================

  /// public URL에서 스토리지 경로를 추출해 삭제
  /// (본인 폴더의 파일만 RLS로 삭제 가능)
  Future<void> deleteByUrl({
    required String bucket,
    required String url,
  }) async {
    final marker = '/object/public/$bucket/';
    final index = url.indexOf(marker);
    if (index < 0) {
      print('[STORAGE] 경로 추출 실패, 삭제 생략: $url');
      return;
    }
    final path = Uri.decodeComponent(url.substring(index + marker.length));
    try {
      await _supabase.storage.from(bucket).remove([path]);
      print('[STORAGE] 삭제 완료: $bucket/$path');
    } catch (e) {
      // 스토리지 삭제 실패는 치명적이지 않으므로 로그만 남긴다
      print('[STORAGE] 삭제 실패 (무시): $e');
    }
  }
}

/// 버킷 이름 상수
class StorageBuckets {
  StorageBuckets._();

  static const String avatars = 'avatars';
  static const String covers = 'covers'; // ← 추가
  static const String villages = 'villages';
  static const String posts = 'posts';
  static const String checkins = 'checkins';
  static const String chatImages = 'chat-images';
}

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});