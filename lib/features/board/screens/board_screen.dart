import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../village/models/village.dart';
import '../models/post.dart';
import '../services/board_service.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

/// 마을 게시판 목록 화면
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, required this.village});

  final Village village;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final _scrollController = ScrollController();

  final List<Post> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// 좋아요 토글 진행 중인 글 id (연타 방지)
  final Set<String> _togglingLikes = {};

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ===========================================================
  // 데이터
  // ===========================================================

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final posts =
          await ref.read(boardServiceProvider).fetchPosts(widget.village.id);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
        _hasMore = posts.length >= BoardService.pageSize;
        _loading = false;
      });
    } catch (e) {
      print('[BOARD] 목록 조회 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('글을 불러오지 못했어요.');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _posts.isEmpty) return;
    _loadingMore = true;

    try {
      final older = await ref.read(boardServiceProvider).fetchPosts(
            widget.village.id,
            before: _posts.last.createdAt,
          );
      if (!mounted) return;
      setState(() {
        _posts.addAll(older);
        _hasMore = older.length >= BoardService.pageSize;
      });
    } catch (e) {
      print('[BOARD] 추가 로드 실패: $e');
    } finally {
      _loadingMore = false;
    }
  }

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<Post>(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(villageId: widget.village.id),
      ),
    );
    if (created != null && mounted) {
      setState(() => _posts.insert(0, created));
    }
  }

  Future<void> _openDetail(int index) async {
    final result = await Navigator.of(context).push<PostDetailResult>(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: _posts[index]),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (result.deleted) {
        _posts.removeAt(index);
      } else {
        _posts[index] = result.post;
      }
    });
  }

  Future<void> _toggleLike(int index) async {
    final post = _posts[index];
    if (_togglingLikes.contains(post.id)) return;
    _togglingLikes.add(post.id);

    final wasLiked = post.isLiked;
    setState(() {
      _posts[index] = post.copyWith(
        isLiked: !wasLiked,
        likeCount: post.likeCount + (wasLiked ? -1 : 1),
      );
    });

    try {
      await ref.read(boardServiceProvider).toggleLike(
            postId: post.id,
            currentlyLiked: wasLiked,
          );
    } catch (e) {
      print('[BOARD] 좋아요 실패: $e');
      if (!mounted) return;
      setState(() {
        _posts[index] = post; // 롤백
      });
    } finally {
      _togglingLikes.remove(post.id);
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
      appBar: AppBar(title: Text('${widget.village.name} 게시판')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textOnPrimary,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('글쓰기'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _posts.isEmpty
                ? _emptyView()
                : RefreshIndicator(
                    onRefresh: _fetch,
                    color: AppTheme.primary,
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                      itemCount: _posts.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) => _postCard(i),
                    ),
                  ),
      ),
    );
  }

  Widget _postCard(int index) {
    final post = _posts[index];

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        onTap: () => _openDetail(index),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- 작성자 ----
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.bgSoft,
                    backgroundImage: post.authorAvatarUrl != null
                        ? CachedNetworkImageProvider(post.authorAvatarUrl!)
                        : null,
                    child: post.authorAvatarUrl == null
                        ? Text(
                            post.authorNickname.characters.first,
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
                    post.authorNickname,
                    style: AppTheme.body(size: 13, weight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    post.relativeTime,
                    style: AppTheme.body(size: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ---- 본문 미리보기 ----
              Text(
                post.content,
                style: AppTheme.body(size: 14, height: 1.5),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // ---- 첫 이미지 썸네일 ----
              if (post.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: post.imageUrls.first,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: 160,
                          color: AppTheme.bgSoft,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 160,
                          color: AppTheme.bgSoft,
                          child: const Center(
                            child: Icon(Icons.broken_image_rounded,
                                color: AppTheme.textLight),
                          ),
                        ),
                      ),
                      if (post.imageUrls.length > 1)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.textMain.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFull),
                            ),
                            child: Text(
                              '+${post.imageUrls.length - 1}',
                              style: AppTheme.body(
                                size: 11,
                                color: AppTheme.bgCard,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // ---- 좋아요/댓글 ----
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _toggleLike(index),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            post.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_outline_rounded,
                            size: 18,
                            color: post.isLiked
                                ? AppTheme.error
                                : AppTheme.textLight,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${post.likeCount}',
                            style: AppTheme.body(
                              size: 12,
                              color: AppTheme.textSub,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.chat_bubble_outline_rounded,
                      size: 16, color: AppTheme.textLight),
                  const SizedBox(width: 4),
                  Text(
                    '${post.commentCount}',
                    style: AppTheme.body(
                      size: 12,
                      color: AppTheme.textSub,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📝', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            '아직 글이 없어요\n첫 소식을 올려 보세요!',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 14,
              color: AppTheme.textSub,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}