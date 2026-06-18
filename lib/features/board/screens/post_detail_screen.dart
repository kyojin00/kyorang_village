import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/safety_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fullscreen_image_viewer.dart';
import '../../../core/widgets/report_dialog.dart';
import '../../friend/widgets/profile_sheet.dart';
import '../models/post.dart';
import '../services/board_service.dart';

class PostDetailResult {
  const PostDetailResult({required this.post, this.deleted = false});

  final Post post;
  final bool deleted;
}

/// 글 상세 화면 (본문 + 이미지 + 반응 + 댓글)
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
  bool _settingReaction = false;

  String get _myId => AuthService.instance.currentUserId ?? '';
  bool get _isAuthor => _post.authorId == _myId;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadComments();
    _refreshPost();
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

  /// 상세 진입 시 최신 반응 정보로 갱신
  Future<void> _refreshPost() async {
    try {
      final fresh = await ref.read(boardServiceProvider).fetchPost(_post.id);
      if (!mounted) return;
      setState(() => _post = fresh);
    } catch (e) {
      print('[POST_DETAIL] 게시글 갱신 실패: $e');
    }
  }

  // ===========================================================
  // 반응 액션
  // ===========================================================

  /// 반응 변경. 같은 걸 다시 누르면 제거, 다른 걸 누르면 변경.
  Future<void> _setReaction(PostReaction? newReaction) async {
    if (_settingReaction) return;
    final old = _post.myReaction;

    final target = (old == newReaction) ? null : newReaction;

    // 낙관적 업데이트
    final newReactions = Map<String, int>.from(_post.reactions);
    if (old != null) {
      final c = (newReactions[old.code] ?? 1) - 1;
      if (c <= 0) {
        newReactions.remove(old.code);
      } else {
        newReactions[old.code] = c;
      }
    }
    if (target != null) {
      newReactions[target.code] = (newReactions[target.code] ?? 0) + 1;
    }

    final wasLikedAny = old != null;
    final nowLikedAny = target != null;
    final likeCountDelta = (nowLikedAny ? 1 : 0) - (wasLikedAny ? 1 : 0);

    setState(() {
      _post = _post.copyWith(
        myReaction: target,
        clearMyReaction: target == null,
        reactions: newReactions,
        likeCount: _post.likeCount + likeCountDelta,
        isLiked: nowLikedAny,
      );
      _settingReaction = true;
    });

    try {
      await ref.read(boardServiceProvider).setReaction(
            postId: _post.id,
            reaction: target,
          );
    } catch (e) {
      print('[POST_DETAIL] 반응 변경 실패: $e');
      if (!mounted) return;
      // 롤백 — 서버에서 최신 상태 다시 가져오기
      _refreshPost();
    } finally {
      if (mounted) setState(() => _settingReaction = false);
    }
  }

  /// 이모지 픽커 시트 (반응 버튼 탭)
  void _showReactionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '반응 선택',
                style: AppTheme.body(size: 14, color: AppTheme.textLight),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: PostReaction.values.map((r) {
                  final selected = _post.myReaction == r;
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _setReaction(r);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withOpacity(0.12)
                            : AppTheme.bgSoft,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusM),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.emoji,
                              style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 4),
                          Text(
                            r.label,
                            style: AppTheme.body(
                              size: 11,
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textSub,
                              weight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // 댓글 액션
  // ===========================================================

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
      Navigator.of(context).pop(PostDetailResult(post: _post, deleted: true));
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
                        style:
                            AppTheme.body(size: 14, color: AppTheme.error)),
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
                    _reactionArea(),
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
      child: GestureDetector(
        onTap: () => FullscreenImageViewer.show(context, url),
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
      ),
    );
  }

  /// 반응 영역 - 카운트 칩 + 반응 버튼 + 댓글 카운트
  Widget _reactionArea() {
    final entries = _post.reactions.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 반응 카운트 칩들
        if (entries.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: entries.map((e) {
              final reaction = PostReaction.fromCode(e.key);
              if (reaction == null) return const SizedBox.shrink();
              final mine = _post.myReaction == reaction;
              return GestureDetector(
                onTap: _settingReaction
                    ? null
                    : () => _setReaction(reaction),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: mine
                        ? AppTheme.primary.withOpacity(0.12)
                        : AppTheme.bgSoft,
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(
                      color: mine
                          ? AppTheme.primary
                          : AppTheme.divider,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(reaction.emoji,
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        '${e.value}',
                        style: AppTheme.body(
                          size: 12,
                          color: mine
                              ? AppTheme.primary
                              : AppTheme.textSub,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],

        // 반응 버튼 + 댓글 카운트
        Row(
          children: [
            GestureDetector(
              onTap: _settingReaction ? null : _showReactionPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _post.myReaction != null
                      ? AppTheme.primary.withOpacity(0.08)
                      : AppTheme.bgSoft,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_post.myReaction != null) ...[
                      Text(
                        _post.myReaction!.emoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _post.myReaction!.label,
                        style: AppTheme.body(
                          size: 12,
                          color: AppTheme.primary,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ] else ...[
                      const Icon(
                        Icons.add_reaction_outlined,
                        size: 18,
                        color: AppTheme.textSub,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '반응',
                        style: AppTheme.body(
                          size: 12,
                          color: AppTheme.textSub,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
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