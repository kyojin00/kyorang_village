import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/safety_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/unread_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fullscreen_image_viewer.dart';
import '../../../core/widgets/report_dialog.dart';
import '../models/friend.dart';
import '../services/dm_service.dart';

/// 1:1 DM 채팅 화면
class DmChatScreen extends ConsumerStatefulWidget {
  const DmChatScreen({super.key, required this.room});

  final DmRoom room;

  @override
  ConsumerState<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends ConsumerState<DmChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final List<DmMessage> _messages = [];
  final Set<String> _messageIds = {};

  RealtimeChannel? _channel;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _uploadingImage = false;
  bool _blocked = false;

  String get _myId => AuthService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    final channel = _channel;
    if (channel != null) {
      DmService.instance.unsubscribe(channel);
    }
    super.dispose();
  }

  // ===========================================================
  // 초기화 / 데이터
  // ===========================================================

  Future<void> _init() async {
    final service = ref.read(dmServiceProvider);

    _blocked =
        await SafetyService.instance.isBlocked(widget.room.otherUserId);

    _channel = service.subscribe(
      roomId: widget.room.id,
      onMessage: _appendMessage,
    );

    try {
      final recent = await service.fetchRecent(widget.room.id);
      if (!mounted) return;
      setState(() {
        for (final m in recent) {
          if (_messageIds.add(m.id)) _messages.add(m);
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _hasMore = recent.length >= 50;
        _loading = false;
      });

      // 방 진입 → 읽음 처리
      ref.read(unreadCountsProvider.notifier).markDmRead(widget.room.id);
    } catch (e) {
      print('[DM_CHAT] 초기 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('대화를 불러오지 못했어요.');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    _loadingMore = true;

    try {
      final older = await ref.read(dmServiceProvider).fetchBefore(
            widget.room.id,
            _messages.first.createdAt,
          );
      if (!mounted) return;
      setState(() {
        final fresh = older.where((m) => _messageIds.add(m.id)).toList();
        _messages.insertAll(0, fresh);
        _hasMore = older.length >= 50;
      });
    } catch (e) {
      print('[DM_CHAT] 과거 메시지 로드 실패: $e');
    } finally {
      _loadingMore = false;
    }
  }

  void _appendMessage(DmMessage message) {
    if (!mounted) return;
    if (!_messageIds.add(message.id)) return;
    setState(() => _messages.add(message));

    // 본인이 받은 메시지면 즉시 읽음 처리
    // (방 열린 상태에서 도착한 메시지)
    if (message.senderId != _myId) {
      ref.read(unreadCountsProvider.notifier).markDmRead(widget.room.id);
    }
  }

  // ===========================================================
  // 전송
  // ===========================================================

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    final channel = _channel;
    if (text.isEmpty || _sending || channel == null) return;

    setState(() => _sending = true);
    _inputController.clear();

    try {
      final message = await ref.read(dmServiceProvider).send(
            roomId: widget.room.id,
            content: text,
            channel: channel,
          );
      _appendMessage(message);
    } catch (e) {
      print('[DM_CHAT] 전송 실패: $e');
      if (!mounted) return;
      _inputController.text = text;
      _snack('메시지를 보내지 못했어요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final channel = _channel;
    if (_uploadingImage || channel == null) return;

    final XFile? file = await ref.read(storageServiceProvider).pickImage();
    if (file == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadImage(
            bucket: StorageBuckets.chatImages,
            file: file,
          );

      final message = await ref.read(dmServiceProvider).send(
            roomId: widget.room.id,
            imageUrl: url,
            channel: channel,
          );
      _appendMessage(message);
    } catch (e) {
      print('[DM_CHAT] 이미지 전송 실패: $e');
      if (!mounted) return;
      _snack('이미지를 보내지 못했어요.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 메시지 길게 누르기 메뉴 (복사 / 신고)
  void _showMessageActions(DmMessage message) {
    final hasText = message.content != null && message.content!.isNotEmpty;
    final isMine = message.senderId == _myId;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              ListTile(
                leading: const Icon(Icons.copy_rounded,
                    color: AppTheme.textMain),
                title: Text('복사하기', style: AppTheme.body(size: 14)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  Clipboard.setData(
                      ClipboardData(text: message.content!));
                  _snack('복사했어요.');
                },
              ),
            if (!isMine)
              ListTile(
                leading:
                    const Icon(Icons.flag_outlined, color: AppTheme.error),
                title: Text('메시지 신고',
                    style:
                        AppTheme.body(size: 14, color: AppTheme.error)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  showReportDialog(
                    context,
                    targetType: ReportTargetType.message,
                    targetId: message.id,
                    targetLabel: '메시지',
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: Text(widget.room.otherNickname)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _emptyView()
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final index = _messages.length - 1 - i;
                            return _messageItem(index);
                          },
                        ),
            ),
            _blocked ? _blockedBar() : _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _messageItem(int index) {
    final message = _messages[index];
    final isMine = message.senderId == _myId;
    final prev = index > 0 ? _messages[index - 1] : null;

    final showDateDivider =
        prev == null || !_isSameDay(prev.createdAt, message.createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDateDivider) _dateDivider(message.createdAt),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isMine) ...[
                _timeText(message.createdAt),
                const SizedBox(width: 6),
              ],
              Flexible(child: _bubble(message, isMine)),
              if (!isMine) ...[
                const SizedBox(width: 6),
                _timeText(message.createdAt),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 메시지 버블 — 이미지/텍스트/혼합 모두 처리
  Widget _bubble(DmMessage message, bool isMine) {
    final hasImage = message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasText = message.content != null && message.content!.isNotEmpty;

    // 이미지만 있는 경우 — 버블 배경 없이 이미지만
    if (hasImage && !hasText) {
      return GestureDetector(
        onLongPress: () => _showMessageActions(message),
        child: _imageOnlyBubble(message.imageUrl!),
      );
    }

    // 텍스트만 있는 경우 — 기존 버블
    if (hasText && !hasImage) {
      return GestureDetector(
        onLongPress: () => _showMessageActions(message),
        child: _textBubble(message.content!, isMine),
      );
    }

    // 이미지 + 텍스트 — 이미지 위 텍스트 아래
    return GestureDetector(
      onLongPress: () => _showMessageActions(message),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _imageOnlyBubble(message.imageUrl!),
          const SizedBox(height: 4),
          _textBubble(message.content!, isMine),
        ],
      ),
    );
  }

  Widget _textBubble(String content, bool isMine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? AppTheme.primary : AppTheme.bgCard,
        border:
            isMine ? null : Border.all(color: AppTheme.divider, width: 1),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppTheme.radiusM),
          topRight: const Radius.circular(AppTheme.radiusM),
          bottomLeft: Radius.circular(isMine ? AppTheme.radiusM : 4),
          bottomRight: Radius.circular(isMine ? 4 : AppTheme.radiusM),
        ),
      ),
      child: Text(
        content,
        style: AppTheme.body(
          size: 14,
          color: isMine ? AppTheme.textOnPrimary : AppTheme.textMain,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _imageOnlyBubble(String imageUrl) {
    return GestureDetector(
      onTap: () => FullscreenImageViewer.show(context, imageUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 220,
            maxHeight: 280,
          ),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 220,
              height: 180,
              color: AppTheme.bgSoft,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 220,
              height: 180,
              color: AppTheme.bgSoft,
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppTheme.textLight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateDivider(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '${date.year}년 ${date.month}월 ${date.day}일',
              style: AppTheme.body(size: 11, color: AppTheme.textLight),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _timeText(DateTime time) {
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final ampm = time.hour < 12 ? '오전' : '오후';
    final minute = time.minute.toString().padLeft(2, '0');
    return Text(
      '$ampm $hour12:$minute',
      style: AppTheme.body(size: 10, color: AppTheme.textLight),
    );
  }

  Widget _blockedBar() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Text(
        '차단한 이웃이에요. 차단을 해제하면 다시 대화할 수 있어요.',
        textAlign: TextAlign.center,
        style: AppTheme.body(size: 13, color: AppTheme.textLight),
      ),
    );
  }

  Widget _inputBar() {
    final busy = _sending || _uploadingImage;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: busy ? null : _pickAndSendImage,
            icon: _uploadingImage
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppTheme.textSub,
                  ),
            tooltip: '사진 보내기',
          ),
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: AppTheme.body(size: 14),
              decoration: InputDecoration(
                hintText: '${widget.room.otherNickname}님에게 한마디',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: busy ? null : _sendText,
            icon: _sending
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

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('💬', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 12),
          Text(
            '${widget.room.otherNickname}님과의 첫 대화예요\n반갑게 인사해 보세요!',
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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}