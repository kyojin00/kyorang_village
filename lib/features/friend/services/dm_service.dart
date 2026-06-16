import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/safety_service.dart';
import '../models/friend.dart';

/// 1:1 DM 서비스
class DmService {
  DmService._();
  static final DmService instance = DmService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// dm_rooms ↔ profiles 셀프 관계 2개 → FK 별칭 필수
  static const String _roomSelect = '*, '
      'user1:profiles!dm_rooms_user1_id_fkey(nickname, avatar_url), '
      'user2:profiles!dm_rooms_user2_id_fkey(nickname, avatar_url)';

  String channelName(String roomId) => 'dm:$roomId';

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  // ===========================================================
  // 방
  // ===========================================================

  Future<List<DmRoom>> fetchRooms() async {
    final rows = await _supabase
        .from('dm_rooms')
        .select(_roomSelect)
        .or('user1_id.eq.$_uid,user2_id.eq.$_uid')
        .order('last_message_at', ascending: false, nullsFirst: false);

    final blockedIds = await SafetyService.instance.fetchBlockedIds();
    return rows
        .map((r) => DmRoom.fromJson(r, _uid))
        .where((room) => !blockedIds.contains(room.otherUserId))
        .toList();
  }

  Future<DmRoom> openRoomWith(String otherUserId) async {
    final sorted = [_uid, otherUserId]..sort();
    final user1 = sorted[0];
    final user2 = sorted[1];

    final existing = await _supabase
        .from('dm_rooms')
        .select(_roomSelect)
        .eq('user1_id', user1)
        .eq('user2_id', user2)
        .maybeSingle();

    if (existing != null) {
      return DmRoom.fromJson(existing, _uid);
    }

    try {
      final row = await _supabase
          .from('dm_rooms')
          .insert({
            'user1_id': user1,
            'user2_id': user2,
          })
          .select(_roomSelect)
          .single();

      print('[DM] 방 생성: ${row['id']}');
      return DmRoom.fromJson(row, _uid);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final retry = await _supabase
            .from('dm_rooms')
            .select(_roomSelect)
            .eq('user1_id', user1)
            .eq('user2_id', user2)
            .single();
        return DmRoom.fromJson(retry, _uid);
      }
      rethrow;
    }
  }

  // ===========================================================
  // 메시지
  // ===========================================================

  Future<List<DmMessage>> fetchRecent(
    String roomId, {
    int limit = 50,
  }) async {
    final rows = await _supabase
        .from('dm_messages')
        .select()
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(limit);

    return rows.map(DmMessage.fromJson).toList().reversed.toList();
  }

  Future<List<DmMessage>> fetchBefore(
    String roomId,
    DateTime before, {
    int limit = 50,
  }) async {
    final rows = await _supabase
        .from('dm_messages')
        .select()
        .eq('room_id', roomId)
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);

    return rows.map(DmMessage.fromJson).toList().reversed.toList();
  }

  /// 메시지 전송
  /// [content] 텍스트 / [imageUrl] 이미지 URL. 둘 중 하나는 있어야 한다.
  Future<DmMessage> send({
    required String roomId,
    String? content,
    String? imageUrl,
    required RealtimeChannel channel,
  }) async {
    final trimmed = content?.trim();
    if ((trimmed == null || trimmed.isEmpty) &&
        (imageUrl == null || imageUrl.isEmpty)) {
      throw Exception('메시지 내용 또는 이미지가 필요합니다.');
    }

    final row = await _supabase
        .from('dm_messages')
        .insert({
          'room_id': roomId,
          'sender_id': _uid,
          'content': (trimmed?.isEmpty ?? true) ? null : trimmed,
          'image_url': imageUrl,
        })
        .select()
        .single();

    final message = DmMessage.fromJson(row);

    try {
      await channel.sendBroadcastMessage(
        event: 'new_message',
        payload: message.toBroadcastJson(),
      );
    } catch (e) {
      print('[DM] broadcast 실패 (저장은 완료): $e');
    }

    return message;
  }

  // ===========================================================
  // 채널
  // ===========================================================

  RealtimeChannel subscribe({
    required String roomId,
    required void Function(DmMessage message) onMessage,
  }) {
    final channel = _supabase.channel(channelName(roomId));

    channel.onBroadcast(
      event: 'new_message',
      callback: (payload) {
        try {
          onMessage(DmMessage.fromJson(payload));
        } catch (e) {
          print('[DM] broadcast 파싱 실패: $e');
        }
      },
    );

    channel.subscribe((status, error) {
      print('[DM] 채널 상태: $status ${error ?? ''}');
    });

    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }
}

final dmServiceProvider = Provider<DmService>((ref) {
  return DmService.instance;
});