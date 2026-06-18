/// 이모지 반응 종류 (DB의 post_likes.reaction 컬럼과 1:1)
enum PostReaction {
  heart('heart', '❤️', '좋아요'),
  thumbsUp('thumbs_up', '👍', '응원'),
  laugh('laugh', '😂', '웃김'),
  sad('sad', '😢', '슬픔'),
  wow('wow', '😮', '놀람'),
  pray('pray', '🙏', '감사');

  const PostReaction(this.code, this.emoji, this.label);

  final String code;
  final String emoji;
  final String label;

  static PostReaction? fromCode(String? code) {
    if (code == null) return null;
    for (final r in PostReaction.values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

/// 게시글 모델 (posts + profiles 조인)
class Post {
  const Post({
    required this.id,
    required this.villageId,
    required this.authorId,
    required this.authorNickname,
    required this.content,
    required this.imageUrls,
    required this.likeCount,
    required this.commentCount,
    required this.createdAt,
    this.authorAvatarUrl,
    this.isLiked = false,
    this.myReaction,
    this.reactions = const {},
  });

  final String id;
  final String villageId;
  final String authorId;
  final String authorNickname;
  final String? authorAvatarUrl;
  final String content;
  final List<String> imageUrls;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;

  /// 본인이 누른 반응 (null이면 안 누름)
  final PostReaction? myReaction;

  /// 게시글별 반응 카운트 (reaction code -> count)
  /// 예: {'heart': 3, 'thumbs_up': 2}
  final Map<String, int> reactions;

  /// 호환성용 (이전 코드들이 isLiked로 토글 표시함)
  /// 어떤 반응이라도 눌렀으면 true
  final bool isLiked;

  factory Post.fromJson(
    Map<String, dynamic> json, {
    bool isLiked = false,
    PostReaction? myReaction,
    Map<String, int> reactions = const {},
  }) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return Post(
      id: json['id'] as String,
      villageId: json['village_id'] as String,
      authorId: json['author_id'] as String,
      authorNickname: profile?['nickname'] as String? ?? '알 수 없음',
      authorAvatarUrl: profile?['avatar_url'] as String?,
      content: json['content'] as String? ?? '',
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      isLiked: isLiked || myReaction != null,
      myReaction: myReaction,
      reactions: reactions,
    );
  }

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    PostReaction? myReaction,
    bool clearMyReaction = false,
    Map<String, int>? reactions,
  }) {
    return Post(
      id: id,
      villageId: villageId,
      authorId: authorId,
      authorNickname: authorNickname,
      authorAvatarUrl: authorAvatarUrl,
      content: content,
      imageUrls: imageUrls,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt,
      isLiked: isLiked ?? this.isLiked,
      myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
      reactions: reactions ?? this.reactions,
    );
  }

  /// 목록 카드용 상대 시간 표시 (방금 전 / N분 전 / N시간 전 / N일 전 / 날짜)
  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${createdAt.year}.${createdAt.month}.${createdAt.day}';
  }
}

/// 댓글 모델 (comments + profiles 조인)
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorNickname,
    required this.content,
    required this.createdAt,
    this.authorAvatarUrl,
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorNickname;
  final String? authorAvatarUrl;
  final String content;
  final DateTime createdAt;

  factory Comment.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return Comment(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      authorId: json['author_id'] as String,
      authorNickname: profile?['nickname'] as String? ?? '알 수 없음',
      authorAvatarUrl: profile?['avatar_url'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${createdAt.year}.${createdAt.month}.${createdAt.day}';
  }
}