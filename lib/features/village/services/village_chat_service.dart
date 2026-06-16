import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/village.dart';

/// 마을 채팅 메시지 모델 (village_messages + profiles 조인)
class VillageMessage {
  const VillageMessage({
    required this.id,
    required this.villageId,
    required this.senderId,
    required this.senderNickname,
    required this.createdAt,
    this.senderAvatarUrl,
    this.content,
    this.imageUrl,
    this.mentions = const [],
  });

  final String id;
  final String villageId;
  final String senderId;
  final String senderNickname;
  final String? senderAvatarUrl;
  final String? content;
  final String? imageUrl;
  final DateTime createdAt;

  /// 멘션된 user id 목록 (uuid 배열)
  final List<String> mentions;

  factory VillageMessage.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final mentionsRaw = json['mentions'];
    final mentionsList = <String>[];
    if (mentionsRaw is List) {
      for (final m in mentionsRaw) {
        if (m is String) mentionsList.add(m);
      }
    }
    return VillageMessage(
      id: json['id'] as String,
      villageId: json['village_id'] as String,
      senderId: json['sender_id'] as String,
      senderNickname: profile?['nickname'] as String? ??
          json['sender_nickname'] as String? ??
          '알 수 없음',
      senderAvatarUrl: profile?['avatar_url'] as String? ??
          json['sender_avatar_url'] as String?,
      content: json['content'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      mentions: mentionsList,
    );
  }

  Map<String, dynamic> toBroadcastJson() {
    return {
      'id': id,
      'village_id': villageId,
      'sender_id': senderId,
      'sender_nickname': senderNickname,
      'sender_avatar_url': senderAvatarUrl,
      'content': content,
      'image_url': imageUrl,
      'mentions': mentions,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// 마을 채팅 서비스
class VillageChatService {
  VillageChatService._();
  static final VillageChatService instance = VillageChatService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  String channelName(String villageId) => 'village_chat:$villageId';

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  // ===========================================================
  // 조회
  // ===========================================================

  Future<List<VillageMessage>> fetchRecent(
    String villageId, {
    int limit = 50,
  }) async {
    final rows = await _supabase
        .from('village_messages')
        .select('*, profiles(nickname, avatar_url)')
        .eq('village_id', villageId)
        .order('created_at', ascending: false)
        .limit(limit);

    final messages = rows.map(VillageMessage.fromJson).toList();
    return messages.reversed.toList();
  }

  Future<List<VillageMessage>> fetchBefore(
    String villageId,
    DateTime before, {
    int limit = 50,
  }) async {
    final rows = await _supabase
        .from('village_messages')
        .select('*, profiles(nickname, avatar_url)')
        .eq('village_id', villageId)
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);

    final messages = rows.map(VillageMessage.fromJson).toList();
    return messages.reversed.toList();
  }

  Future<List<VillageMember>> fetchMembers(String villageId) async {
    final rows = await _supabase
        .from('village_members')
        .select('*, profiles(nickname, avatar_url)')
        .eq('village_id', villageId)
        .neq('user_id', _uid);

    final members = rows.map(VillageMember.fromJson).toList();
    members.sort((a, b) => a.nickname.compareTo(b.nickname));
    return members;
  }

  // ===========================================================
  // 송신
  // ===========================================================

  /// 메시지 전송
  /// [content] 텍스트 / [imageUrl] 이미지 URL. 둘 중 하나는 있어야 한다.
  /// [mentions] 멘션된 user id 목록.
  Future<VillageMessage> send({
    required String villageId,
    String? content,
    String? imageUrl,
    required RealtimeChannel channel,
    List<String> mentions = const [],
  }) async {
    final trimmed = content?.trim();
    if ((trimmed == null || trimmed.isEmpty) &&
        (imageUrl == null || imageUrl.isEmpty)) {
      throw Exception('메시지 내용 또는 이미지가 필요합니다.');
    }

    final row = await _supabase
        .from('village_messages')
        .insert({
          'village_id': villageId,
          'sender_id': _uid,
          'content': (trimmed?.isEmpty ?? true) ? null : trimmed,
          'image_url': imageUrl,
          'mentions': mentions,
        })
        .select('*, profiles(nickname, avatar_url)')
        .single();

    final message = VillageMessage.fromJson(row);

    try {
      await channel.sendBroadcastMessage(
        event: 'new_message',
        payload: message.toBroadcastJson(),
      );
    } catch (e) {
      print('[VILLAGE_CHAT] broadcast 실패 (저장은 완료): $e');
    }

    return message;
  }

  // ===========================================================
  // 채널
  // ===========================================================

  RealtimeChannel subscribe({
    required String villageId,
    required void Function(VillageMessage message) onMessage,
  }) {
    final channel = _supabase.channel(channelName(villageId));

    channel.onBroadcast(
      event: 'new_message',
      callback: (payload) {
        try {
          final message = VillageMessage.fromJson(payload);
          onMessage(message);
        } catch (e) {
          print('[VILLAGE_CHAT] broadcast 파싱 실패: $e');
        }
      },
    );

    channel.subscribe((status, error) {
      print('[VILLAGE_CHAT] 채널 상태: $status ${error ?? ''}');
    });

    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }
}

final villageChatServiceProvider = Provider<VillageChatService>((ref) {
  return VillageChatService.instance;
});