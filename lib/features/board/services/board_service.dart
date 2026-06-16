import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/safety_service.dart';
import '../../../core/services/storage_service.dart';
import '../models/post.dart';

/// 게시판 데이터 서비스 (글/댓글/좋아요)
class BoardService {
  BoardService._();
  static final BoardService instance = BoardService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const int pageSize = 20;

  /// posts ↔ profiles 관계가 두 개(작성자 FK, post_likes 다대다)라서
  /// 작성자 조인은 FK 이름을 명시해야 한다 (PGRST201 방지)
  static const String _postSelect =
      '*, profiles!posts_author_id_fkey(nickname, avatar_url)';

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  // ===========================================================
  // 글 조회
  // ===========================================================

  /// 마을 게시글 목록 (최신순, [before] 이전 글로 페이지네이션)
  /// 각 글에 isLiked를 채워서 반환한다.
  Future<List<Post>> fetchPosts(
    String villageId, {
    DateTime? before,
  }) async {
    var query = _supabase
        .from('posts')
        .select(_postSelect)
        .eq('village_id', villageId);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await query
        .order('created_at', ascending: false)
        .limit(pageSize);

    if (rows.isEmpty) return [];

    // 차단한 유저 글 제외
    final blockedIds = await SafetyService.instance.fetchBlockedIds();
    final visibleRows = blockedIds.isEmpty
        ? rows
        : rows
            .where((r) => !blockedIds.contains(r['author_id'] as String))
            .toList();

    if (visibleRows.isEmpty) return [];

    // 내가 좋아요 누른 글 id 조회 (이번 페이지 글들만)
    final postIds = visibleRows.map((r) => r['id'] as String).toList();
    final likedRows = await _supabase
        .from('post_likes')
        .select('post_id')
        .eq('user_id', _uid)
        .inFilter('post_id', postIds);
    final likedIds = likedRows.map((r) => r['post_id'] as String).toSet();

    return visibleRows
        .map((r) => Post.fromJson(r, isLiked: likedIds.contains(r['id'])))
        .toList();
  }

  /// 글 단건 조회 (상세 화면 갱신용)
  Future<Post> fetchPost(String postId) async {
    final row = await _supabase
        .from('posts')
        .select(_postSelect)
        .eq('id', postId)
        .single();

    final liked = await _supabase
        .from('post_likes')
        .select('post_id')
        .eq('user_id', _uid)
        .eq('post_id', postId)
        .maybeSingle();

    return Post.fromJson(row, isLiked: liked != null);
  }

  // ===========================================================
  // 글 작성 / 삭제
  // ===========================================================

  Future<Post> createPost({
    required String villageId,
    required String content,
    List<String> imageUrls = const [],
  }) async {
    final row = await _supabase
        .from('posts')
        .insert({
          'village_id': villageId,
          'author_id': _uid,
          'content': content.trim(),
          'image_urls': imageUrls,
        })
        .select(_postSelect)
        .single();

    print('[BOARD] 글 작성: ${row['id']}');
    return Post.fromJson(row);
  }

  /// 글 삭제 (첨부 이미지도 스토리지에서 정리)
  Future<void> deletePost(Post post) async {
    await _supabase.from('posts').delete().eq('id', post.id);
    print('[BOARD] 글 삭제: ${post.id}');

    for (final url in post.imageUrls) {
      await StorageService.instance.deleteByUrl(
        bucket: StorageBuckets.posts,
        url: url,
      );
    }
  }

  // ===========================================================
  // 댓글
  // ===========================================================

  Future<List<Comment>> fetchComments(String postId) async {
    final rows = await _supabase
        .from('comments')
        .select('*, profiles(nickname, avatar_url)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    final blockedIds = await SafetyService.instance.fetchBlockedIds();
    final visibleRows = blockedIds.isEmpty
        ? rows
        : rows
            .where((r) => !blockedIds.contains(r['author_id'] as String))
            .toList();

    return visibleRows.map(Comment.fromJson).toList();
  }

  Future<Comment> addComment({
    required String postId,
    required String content,
  }) async {
    final row = await _supabase
        .from('comments')
        .insert({
          'post_id': postId,
          'author_id': _uid,
          'content': content.trim(),
        })
        .select('*, profiles(nickname, avatar_url)')
        .single();

    print('[BOARD] 댓글 작성: ${row['id']}');
    return Comment.fromJson(row);
  }

  Future<void> deleteComment(String commentId) async {
    await _supabase.from('comments').delete().eq('id', commentId);
    print('[BOARD] 댓글 삭제: $commentId');
  }

  // ===========================================================
  // 좋아요
  // ===========================================================

  /// 좋아요 토글. 토글 후 상태(true=좋아요 됨)를 반환한다.
  /// 카운트는 DB 트리거가 유지하므로 클라이언트는 표시값만 증감한다.
  Future<bool> toggleLike({
    required String postId,
    required bool currentlyLiked,
  }) async {
    if (currentlyLiked) {
      await _supabase
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', _uid);
      return false;
    } else {
      await _supabase.from('post_likes').insert({
        'post_id': postId,
        'user_id': _uid,
      });
      return true;
    }
  }
}

final boardServiceProvider = Provider<BoardService>((ref) {
  return BoardService.instance;
});