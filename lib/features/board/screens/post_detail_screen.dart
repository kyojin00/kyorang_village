import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/safety_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/report_dialog.dart';
import '../../friend/widgets/profile_sheet.dart';
import '../models/post.dart';
import '../services/board_service.dart';

/// 글 상세 화면의 pop 결과
/// 목록 화면이 받아서 항목을 갱신하거나 제거한다.
class PostDetailResult {
  const PostDetailResult({required this.post, this.deleted = false});

  final Post post;
  final bool deleted;
}

/// 글 상세 화면 (본문 + 이미지 + 좋아요 + 댓글)
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentController = TextEditingController();

  late Post _post;
  List<Comment> _comments = [];
  bool _loadingComments = true;
  bool _sendingComment = false;
  bool _togglingLike = false;

  String get _myId => AuthService.instance.currentUserId ?? '';
  bool get _isAuthor => _post.authorId == _myId;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _popWithResult() {
    Navigator.of(context).pop(PostDetailResult(post: _post));
  }

  // ===========================================================
  // 데이터
  // ===========================================================

  Future<void> _loadComments() async {
    try {
      final comments =
          await ref.read(boardServiceProvider).fetchComments(_post.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loadingComments = false;
      });
    } catch (e) {
      print('[POST_DETAIL] 댓글 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loadingComments = false);
    }
  }

  // ===========================================================
  // 액션
  // ===========================================================

  Future<void> _toggleLike() async {
    if (_togglingLike) return;
    _togglingLike = true;

    // 낙관적 업데이트
    final wasLiked = _post.isLiked;
    setState(() {
      _post = _post.copyWith(
        isLiked: !wasLiked,
        likeCount: _post.likeCount + (wasLiked ? -1 : 1),
      );
    });

    try {
      await ref.read(boardServiceProvider).toggleLike(
            postId: _post.id,
            currentlyLiked: wasLiked,
          );
    } catch (e) {
      print('[POST_DETAIL] 좋아요 실패: $e');
      if (!mounted) return;
      // 롤백
      setState(() {
        _post = _post.copyWith(
          isLiked: wasLiked,
          likeCount: _post.likeCount + (wasLiked ? 1 : -1),
        );
      });
    } finally {
      _togglingLike = false;
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sendingComment) return;

    setState(() => _sendingComment = true);
    _commentController.clear();
    FocusScope.of(context).unfocus();

    try {
      final comment = await ref.read(boardServiceProvider).addComment(
            postId: _post.id,
            content: text,
          );
      if (!mounted) return;
      setState(() {
        _comments.add(comment);
        _post = _post.copyWith(commentCount: _post.commentCount + 1);
        _sendingComment = false;
      });
    } catch (e) {
      print('[POST_DETAIL] 댓글 작성 실패: $e');
      if (!mounted) return;
      _commentController.text = text;
      setState(() => _sendingComment = false);
      _snack('댓글을 남기지 못했어요.');
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    final ok = await _confirm(title: '댓글 삭제', message: '이 댓글을 삭제할까요?');
    if (ok != true) return;

    try {
      await ref.read(boardServiceProvider).deleteComment(comment.id);
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
        _post = _post.copyWith(commentCount: _post.commentCount - 1);
      });
    } catch (e) {
      print('[POST_DETAIL] 댓글 삭제 실패: $e');
      if (!mounted) return;
      _snack('댓글을 삭제하지 못했어요.');
    }
  }

  Future<void> _deletePost() async {
    final ok = await _confirm(
      title: '글 삭제',
      message: '이 글을 삭제할까요?\n댓글도 함께 사라져요.',
    );
    if (ok != true) return;

    try {
      await ref.read(boardServiceProvider).deletePost(_post);
      if (!mounted) return;
      Navigator.of(context)
          .pop(PostDetailResult(post: _post, deleted: true));
    } catch (e) {
      print('[POST_DETAIL] 글 삭제 실패: $e');
      if (!mounted) return;
      _snack('글을 삭제하지 못했어요.');
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
              '삭제',
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

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithResult();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgMain,
        appBar: AppBar(
          title: const Text('게시글'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _popWithResult,
          ),
          actions: [
            if (_isAuthor)
              IconButton(
                onPressed: _deletePost,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                color: AppTheme.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                onSelected: (value) {
                  if (value == 'report') {
                    showReportDialog(
                      context,
                      targetType: ReportTargetType.post,
                      targetId: _post.id,
                      targetLabel: '게시글',
                    );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'report',
                    child: Text('신고하기',
                        style: AppTheme.body(size: 14, color: AppTheme.error)),
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  children: [
                    _authorRow(),
                    const SizedBox(height: 14),
                    Text(
                      _post.content,
                      style: AppTheme.body(size: 15, height: 1.6),
                    ),
                    if (_post.imageUrls.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ..._post.imageUrls.map(_postImage),
                    ],
                    const SizedBox(height: 14),
                    _reactionRow(),
                    const Divider(height: 32),
                    _commentSection(),
                  ],
                ),
              ),
              _commentInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _authorRow() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusS),
      onTap: () => ProfileSheet.show(
        context,
        userId: _post.authorId,
        nickname: _post.authorNickname,
        avatarUrl: _post.authorAvatarUrl,
      ),
      child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.bgSoft,
          backgroundImage: _post.authorAvatarUrl != null
              ? CachedNetworkImageProvider(_post.authorAvatarUrl!)
              : null,
          child: _post.authorAvatarUrl == null
              ? Text(
                  _post.authorNickname.characters.first,
                  style: AppTheme.body(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _post.authorNickname,
              style: AppTheme.body(size: 14, weight: FontWeight.w700),
            ),
            Text(
              _post.relativeTime,
              style: AppTheme.body(size: 11, color: AppTheme.textLight),
            ),
          ],
        ),
      ],
      ),
    );
  }

  Widget _postImage(String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (_, __) => Container(
            height: 200,
            color: AppTheme.bgSoft,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            height: 120,
            color: AppTheme.bgSoft,
            child: const Center(
              child: Icon(Icons.broken_image_rounded,
                  color: AppTheme.textLight),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reactionRow() {
    return Row(
      children: [
        GestureDetector(
          onTap: _toggleLike,
          child: Row(
            children: [
              Icon(
                _post.isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_outline_rounded,
                size: 20,
                color:
                    _post.isLiked ? AppTheme.error : AppTheme.textLight,
              ),
              const SizedBox(width: 4),
              Text(
                '${_post.likeCount}',
                style: AppTheme.body(
                  size: 13,
                  color: AppTheme.textSub,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        const Icon(Icons.chat_bubble_outline_rounded,
            size: 18, color: AppTheme.textLight),
        const SizedBox(width: 4),
        Text(
          '${_post.commentCount}',
          style: AppTheme.body(
            size: 13,
            color: AppTheme.textSub,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _commentSection() {
    if (_loadingComments) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '아직 댓글이 없어요. 첫 댓글을 남겨 보세요!',
            style: AppTheme.body(size: 13, color: AppTheme.textLight),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _comments.map((c) {
        final mine = c.authorId == _myId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => ProfileSheet.show(
                  context,
                  userId: c.authorId,
                  nickname: c.authorNickname,
                  avatarUrl: c.authorAvatarUrl,
                ),
                child: CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.bgSoft,
                backgroundImage: c.authorAvatarUrl != null
                    ? CachedNetworkImageProvider(c.authorAvatarUrl!)
                    : null,
                child: c.authorAvatarUrl == null
                    ? Text(
                        c.authorNickname.characters.first,
                        style: AppTheme.body(
                          size: 11,
                          weight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      )
                    : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c.authorNickname,
                          style: AppTheme.body(
                              size: 13, weight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.relativeTime,
                          style: AppTheme.body(
                              size: 10, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.content,
                      style: AppTheme.body(size: 14, height: 1.5),
                    ),
                  ],
                ),
              ),
              if (mine)
                GestureDetector(
                  onTap: () => _deleteComment(c),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: AppTheme.textLight),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => showReportDialog(
                    context,
                    targetType: ReportTargetType.comment,
                    targetId: c.id,
                    targetLabel: '댓글',
                  ),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.flag_outlined,
                        size: 15, color: AppTheme.textLight),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _commentInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              minLines: 1,
              maxLines: 3,
              style: AppTheme.body(size: 14),
              decoration: const InputDecoration(
                hintText: '따뜻한 댓글을 남겨 보세요',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _sendingComment ? null : _addComment,
            icon: _sendingComment
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.send_rounded, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}