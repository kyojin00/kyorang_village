/// 친구 관계 모델 (friendships + profiles 양방향 조인)
///
/// friendships는 profiles와 셀프 관계가 2개(requester, addressee)라서
/// 조회 시 반드시 FK 별칭을 명시해야 한다:
///   requester:profiles!friendships_requester_id_fkey(...)
///   addressee:profiles!friendships_addressee_id_fkey(...)
class Friendship {
  const Friendship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
    required this.otherUserId,
    required this.otherNickname,
    this.otherAvatarUrl,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final String status; // pending | accepted
  final DateTime createdAt;

  /// 내 기준 상대방 정보 (조회 시 myId로 결정)
  final String otherUserId;
  final String otherNickname;
  final String? otherAvatarUrl;

  bool get isAccepted => status == 'accepted';
  bool get isPending => status == 'pending';

  /// 내가 보낸 신청인지 (myId 기준)
  bool sentByMe(String myId) => requesterId == myId;

  factory Friendship.fromJson(Map<String, dynamic> json, String myId) {
    final requesterId = json['requester_id'] as String;
    final addresseeId = json['addressee_id'] as String;
    final iAmRequester = requesterId == myId;

    final otherProfile = (iAmRequester
        ? json['addressee']
        : json['requester']) as Map<String, dynamic>?;

    return Friendship(
      id: json['id'] as String,
      requesterId: requesterId,
      addresseeId: addresseeId,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      otherUserId: iAmRequester ? addresseeId : requesterId,
      otherNickname: otherProfile?['nickname'] as String? ?? '알 수 없음',
      otherAvatarUrl: otherProfile?['avatar_url'] as String?,
    );
  }
}

/// DM 방 모델 (dm_rooms + profiles 양방향 조인)
///
/// dm_rooms도 profiles와 셀프 관계 2개(user1, user2) → FK 별칭 필수:
///   user1:profiles!dm_rooms_user1_id_fkey(...)
///   user2:profiles!dm_rooms_user2_id_fkey(...)
class DmRoom {
  const DmRoom({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    required this.createdAt,
    required this.otherUserId,
    required this.otherNickname,
    this.otherAvatarUrl,
    this.lastMessage,
    this.lastMessageAt,
  });

  final String id;
  final String user1Id;
  final String user2Id;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime createdAt;

  /// 내 기준 상대방 정보
  final String otherUserId;
  final String otherNickname;
  final String? otherAvatarUrl;

  factory DmRoom.fromJson(Map<String, dynamic> json, String myId) {
    final user1Id = json['user1_id'] as String;
    final user2Id = json['user2_id'] as String;
    final iAmUser1 = user1Id == myId;

    final otherProfile =
        (iAmUser1 ? json['user2'] : json['user1']) as Map<String, dynamic>?;

    return DmRoom(
      id: json['id'] as String,
      user1Id: user1Id,
      user2Id: user2Id,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String).toLocal()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      otherUserId: iAmUser1 ? user2Id : user1Id,
      otherNickname: otherProfile?['nickname'] as String? ?? '알 수 없음',
      otherAvatarUrl: otherProfile?['avatar_url'] as String?,
    );
  }

  /// 목록용 마지막 메시지 시간 표시
  String get lastMessageTimeLabel {
    final t = lastMessageAt;
    if (t == null) return '';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24 && now.day == t.day) {
      final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final ampm = t.hour < 12 ? '오전' : '오후';
      return '$ampm $hour12:${t.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${diff.inDays == 0 ? 1 : diff.inDays}일 전';
    return '${t.month}.${t.day}';
  }
}

/// DM 메시지 모델 (dm_messages + profiles 조인 / broadcast 평탄화 지원)
class DmMessage {
  const DmMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.createdAt,
    this.content,
    this.imageUrl,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String? content;
  final String? imageUrl;
  final DateTime createdAt;

  factory DmMessage.fromJson(Map<String, dynamic> json) {
    return DmMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toBroadcastJson() {
    return {
      'id': id,
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'image_url': imageUrl,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}