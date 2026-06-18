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
import '../../friend/widgets/profile_sheet.dart';
import '../models/village.dart';
import '../services/village_chat_service.dart';
import '../widgets/mention_picker_sheet.dart';

/// 마을 그룹채팅 화면
class VillageChatScreen extends ConsumerStatefulWidget {
  const VillageChatScreen({super.key, required this.village});

  final Village village;

  @override
  ConsumerState<VillageChatScreen> createState() =>
      _VillageChatScreenState();
}

class _VillageChatScreenState extends ConsumerState<VillageChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final List<VillageMessage> _messages = [];
  final Set<String> _messageIds = {};
  Set<String> _blockedIds = {};

  List<VillageMember> _members = [];

  final Map<String, String> _pendingMentions = {};

  RealtimeChannel? _channel;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _uploadingImage = false;
  bool _mentionSheetOpen = false;

  String get _myId => AuthService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onInputChange);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    final channel = _channel;
    if (channel != null) {
      VillageChatService.instance.unsubscribe(channel);
    }
    super.dispose();
  }

  // ===========================================================
  // 초기화 / 데이터
  // ===========================================================

  Future<void> _init() async {
    final service = ref.read(villageChatServiceProvider);

    _channel = service.subscribe(
      villageId: widget.village.id,
      onMessage: _appendMessage,
    );

    try {
      _blockedIds = await SafetyService.instance.fetchBlockedIds();
      final recent = await service.fetchRecent(widget.village.id);

      service.fetchMembers(widget.village.id).then((members) {
        if (mounted) setState(() => _members = members);
      }).catchError((e) => print('[VILLAGE_CHAT] 멤버 로드 실패: $e'));

      if (!mounted) return;
      setState(() {
        for (final m in recent) {
          if (_blockedIds.contains(m.senderId)) continue;
          if (_messageIds.add(m.id)) _messages.add(m);
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _hasMore = recent.length >= 50;
        _loading = false;
      });

      // 마을 채팅 진입 → 읽음 처리
      ref
          .read(unreadCountsProvider.notifier)
          .markVillageRead(widget.village.id);
    } catch (e) {
      print('[VILLAGE_CHAT] 초기 로드 실패: $e');
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
      final older = await ref.read(villageChatServiceProvider).fetchBefore(
            widget.village.id,
            _messages.first.createdAt,
          );
      if (!mounted) return;
      setState(() {
        final fresh = older
            .where((m) =>
                !_blockedIds.contains(m.senderId) && _messageIds.add(m.id))
            .toList();
        _messages.insertAll(0, fresh);
        _hasMore = older.length >= 50;
      });
    } catch (e) {
      print('[VILLAGE_CHAT] 과거 메시지 로드 실패: $e');
    } finally {
      _loadingMore = false;
    }
  }

  void _appendMessage(VillageMessage message) {
    if (!mounted) return;
    if (_blockedIds.contains(message.senderId)) return;
    if (!_messageIds.add(message.id)) return;
    setState(() => _messages.add(message));

    // 마을 채팅 화면 열린 상태에서 받은 메시지는 즉시 읽음 처리
    if (message.senderId != _myId) {
      ref
          .read(unreadCountsProvider.notifier)
          .markVillageRead(widget.village.id);
    }
  }

  void _showMessageActions(VillageMessage message) {
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
            if (!isMine) ...[
              ListTile(
                leading: const Icon(Icons.person_outline_rounded,
                    color: AppTheme.textMain),
                title: Text('프로필 보기', style: AppTheme.body(size: 14)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  ProfileSheet.show(
                    context,
                    userId: message.senderId,
                    nickname: message.senderNickname,
                    avatarUrl: message.senderAvatarUrl,
                  );
                },
              ),
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
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // 멘션 처리
  // ===========================================================

  void _onInputChange() {
    if (_mentionSheetOpen) return;
    if (_members.isEmpty) return;

    final text = _inputController.text;
    final selection = _inputController.selection;
    if (!selection.isValid || selection.baseOffset <= 0) return;

    final cursor = selection.baseOffset;
    if (cursor > text.length) return;
    final lastChar = text.substring(cursor - 1, cursor);
    if (lastChar != '@') return;

    if (cursor >= 2) {
      final prev = text.substring(cursor - 2, cursor - 1);
      if (RegExp(r'\S').hasMatch(prev) && prev != ' ' && prev != '\n') {
        return;
      }
    }

    _openMentionSheet(cursor);
  }

  Future<void> _openMentionSheet(int atIndex) async {
    if (_mentionSheetOpen) return;
    setState(() => _mentionSheetOpen = true);

    try {
      final picked = await MentionPickerSheet.show(
        context,
        members: _members,
      );
      if (!mounted) return;
      if (picked == null) return;

      _insertMention(picked, atIndex);
    } finally {
      if (mounted) setState(() => _mentionSheetOpen = false);
    }
  }

  void _insertMention(VillageMember member, int atIndex) {
    final text = _inputController.text;
    final before = text.substring(0, atIndex - 1);
    final after = text.substring(atIndex);
    final mentionText = '@${member.nickname} ';
    final newText = before + mentionText + after;

    _inputController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: before.length + mentionText.length,
      ),
    );

    _pendingMentions[mentionText.trim()] = member.userId;
  }

  List<String> _extractActiveMentions(String text) {
    final ids = <String>{};
    _pendingMentions.forEach((mentionStr, userId) {
      if (text.contains(mentionStr)) {
        ids.add(userId);
      }
    });
    return ids.toList();
  }

  // ===========================================================
  // 전송
  // ===========================================================

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    final channel = _channel;
    if (text.isEmpty || _sending || channel == null) return;

    final mentionIds = _extractActiveMentions(text);

    setState(() => _sending = true);
    _inputController.clear();

    try {
      final message = await ref.read(villageChatServiceProvider).send(
            villageId: widget.village.id,
            content: text,
            channel: channel,
            mentions: mentionIds,
          );
      _appendMessage(message);
      _pendingMentions.clear();
    } catch (e) {
      print('[VILLAGE_CHAT] 전송 실패: $e');
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

      final message = await ref.read(villageChatServiceProvider).send(
            villageId: widget.village.id,
            imageUrl: url,
            channel: channel,
          );
      _appendMessage(message);
    } catch (e) {
      print('[VILLAGE_CHAT] 이미지 전송 실패: $e');
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

  // ===========================================================
  // UI
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: Text(widget.village.name)),
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
            _inputBar(),
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
    final showSenderInfo = !isMine &&
        (prev == null ||
            prev.senderId != message.senderId ||
            showDateDivider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDateDivider) _dateDivider(message.createdAt),
        Padding(
          padding: EdgeInsets.only(
            top: showSenderInfo ? 10 : 3,
            bottom: 3,
          ),
          child: isMine
              ? _myBubble(message)
              : _otherBubble(message, showSenderInfo),
        ),
      ],
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

  Widget _myBubble(VillageMessage message) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _timeText(message.createdAt),
        const SizedBox(width: 6),
        Flexible(child: _bubble(message, isMine: true)),
      ],
    );
  }

  Widget _otherBubble(VillageMessage message, bool showSenderInfo) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: showSenderInfo
              ? GestureDetector(
                  onTap: () => ProfileSheet.show(
                    context,
                    userId: message.senderId,
                    nickname: message.senderNickname,
                    avatarUrl: message.senderAvatarUrl,
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.bgSoft,
                    backgroundImage: message.senderAvatarUrl != null
                        ? NetworkImage(message.senderAvatarUrl!)
                        : null,
                    child: message.senderAvatarUrl == null
                        ? Text(
                            message.senderNickname.characters.first,
                            style: AppTheme.body(
                              size: 13,
                              weight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          )
                        : null,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSenderInfo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message.senderNickname,
                    style: AppTheme.body(
                      size: 12,
                      color: AppTheme.textSub,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: _bubble(message, isMine: false)),
                  const SizedBox(width: 6),
                  _timeText(message.createdAt),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 메시지 버블 — 이미지/텍스트/혼합 모두 처리
  Widget _bubble(VillageMessage message, {required bool isMine}) {
    final hasImage = message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasText = message.content != null && message.content!.isNotEmpty;

    if (hasImage && !hasText) {
      return GestureDetector(
        onLongPress: () => _showMessageActions(message),
        child: _imageOnlyBubble(message.imageUrl!),
      );
    }

    if (hasText && !hasImage) {
      return GestureDetector(
        onLongPress: () => _showMessageActions(message),
        child: _textBubble(message.content!, isMine),
      );
    }

    // 둘 다
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
          topLeft: Radius.circular(isMine ? AppTheme.radiusM : 4),
          topRight: const Radius.circular(AppTheme.radiusM),
          bottomLeft: const Radius.circular(AppTheme.radiusM),
          bottomRight: Radius.circular(isMine ? 4 : AppTheme.radiusM),
        ),
      ),
      child: _renderContent(
        content,
        defaultColor:
            isMine ? AppTheme.textOnPrimary : AppTheme.textMain,
        mentionColor: isMine ? Colors.white : AppTheme.primary,
        mentionBackground: isMine
            ? Colors.white.withOpacity(0.18)
            : AppTheme.primary.withOpacity(0.10),
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

  /// 메시지 본문 렌더링 - @닉네임 패턴 강조
  Widget _renderContent(
    String content, {
    required Color defaultColor,
    required Color mentionColor,
    required Color mentionBackground,
  }) {
    final pattern = RegExp(r'@([^\s@.,!?]+)');
    final spans = <InlineSpan>[];
    int last = 0;
    for (final match in pattern.allMatches(content)) {
      if (match.start > last) {
        spans.add(TextSpan(text: content.substring(last, match.start)));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: mentionBackground,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            match.group(0)!,
            style: AppTheme.body(
              size: 14,
              color: mentionColor,
              weight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
      ));
      last = match.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }

    return Text.rich(
      TextSpan(
        style: AppTheme.body(size: 14, color: defaultColor, height: 1.4),
        children: spans,
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
              decoration: const InputDecoration(
                hintText: '이웃들에게 한마디  ( @로 멘션 )',
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
                : const Icon(
                    Icons.send_rounded,
                    color: AppTheme.primary,
                  ),
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
            '아직 대화가 없어요\n첫 인사를 남겨 보세요!',
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