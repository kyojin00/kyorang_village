import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/safety_service.dart';
import '../../../core/services/storage_service.dart';
import '../models/post.dart';

/// 게시판 데이터 서비스 (글/댓글/반응)
class BoardService {
  BoardService._();
  static final BoardService instance = BoardService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const int pageSize = 20;

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

  /// 마을 게시글 목록 (반응 정보 포함)
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

    final blockedIds = await SafetyService.instance.fetchBlockedIds();
    final visibleRows = blockedIds.isEmpty
        ? rows
        : rows
            .where((r) => !blockedIds.contains(r['author_id'] as String))
            .toList();

    if (visibleRows.isEmpty) return [];

    final postIds = visibleRows.map((r) => r['id'] as String).toList();

    final myReactionsByPost = await _fetchMyReactions(postIds);
    final reactionsByPost = await _fetchPostsReactions(postIds);

    return visibleRows.map((r) {
      final id = r['id'] as String;
      return Post.fromJson(
        r,
        myReaction: myReactionsByPost[id],
        reactions: reactionsByPost[id] ?? const {},
        isLiked: myReactionsByPost[id] != null,
      );
    }).toList();
  }

  Future<Post> fetchPost(String postId) async {
    final row = await _supabase
        .from('posts')
        .select(_postSelect)
        .eq('id', postId)
        .single();

    final myReactions = await _fetchMyReactions([postId]);
    final reactions = await _fetchPostsReactions([postId]);

    return Post.fromJson(
      row,
      myReaction: myReactions[postId],
      reactions: reactions[postId] ?? const {},
      isLiked: myReactions[postId] != null,
    );
  }

  /// 내 반응 - postId → PostReaction 매핑
  Future<Map<String, PostReaction>> _fetchMyReactions(
      List<String> postIds) async {
    if (postIds.isEmpty) return const {};
    final result = await _supabase.rpc(
      'get_my_reactions',
      params: {'p_post_ids': postIds},
    );
    final out = <String, PostReaction>{};
    if (result is List) {
      for (final row in result) {
        if (row is! Map) continue;
        final pid = row['post_id'] as String?;
        final code = row['reaction'] as String?;
        if (pid == null || code == null) continue;
        final reaction = PostReaction.fromCode(code);
        if (reaction != null) out[pid] = reaction;
      }
    }
    return out;
  }

  /// 게시글별 반응 카운트 - postId → {reaction code: count}
  Future<Map<String, Map<String, int>>> _fetchPostsReactions(
      List<String> postIds) async {
    if (postIds.isEmpty) return const {};
    final result = await _supabase.rpc(
      'get_posts_reactions',
      params: {'p_post_ids': postIds},
    );
    final out = <String, Map<String, int>>{};
    if (result is List) {
      for (final row in result) {
        if (row is! Map) continue;
        final pid = row['post_id'] as String?;
        final code = row['reaction'] as String?;
        final count = (row['count'] as num?)?.toInt();
        if (pid == null || code == null || count == null) continue;
        (out[pid] ??= <String, int>{})[code] = count;
      }
    }
    return out;
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
  // 반응
  // ===========================================================

  /// 반응 설정/변경/제거 통합 처리
  /// - reaction이 null이면: 본인의 모든 반응 제거
  /// - reaction이 있으면: 본인의 반응을 그것으로 설정 (이미 있으면 갱신)
  ///
  /// 한 user당 한 반응만 가능 (PK가 post_id+user_id)
  Future<void> setReaction({
    required String postId,
    required PostReaction? reaction,
  }) async {
    if (reaction == null) {
      await _supabase
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', _uid);
      return;
    }

    // upsert — 없으면 insert, 있으면 reaction만 갱신
    await _supabase.from('post_likes').upsert(
      {
        'post_id': postId,
        'user_id': _uid,
        'reaction': reaction.code,
      },
      onConflict: 'post_id,user_id',
    );
  }

  /// 기존 코드 호환용 - heart 토글
  Future<bool> toggleLike({
    required String postId,
    required bool currentlyLiked,
  }) async {
    if (currentlyLiked) {
      await setReaction(postId: postId, reaction: null);
      return false;
    } else {
      await setReaction(postId: postId, reaction: PostReaction.heart);
      return true;
    }
  }
}

final boardServiceProvider = Provider<BoardService>((ref) {
  return BoardService.instance;
});