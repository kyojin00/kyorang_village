import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 안읽은 메시지 카운트 데이터
class UnreadCounts {
  const UnreadCounts({
    this.dmByRoom = const {},
    this.villageByVillage = const {},
  });

  /// DM room_id → 안읽은 수
  final Map<String, int> dmByRoom;

  /// 마을 village_id → 안읽은 수
  final Map<String, int> villageByVillage;

  int dmFor(String roomId) => dmByRoom[roomId] ?? 0;
  int villageFor(String villageId) => villageByVillage[villageId] ?? 0;

  int get dmTotal =>
      dmByRoom.values.fold<int>(0, (sum, v) => sum + v);

  int get villageTotal =>
      villageByVillage.values.fold<int>(0, (sum, v) => sum + v);

  int get totalAll => dmTotal + villageTotal;

  bool get hasAny => dmByRoom.isNotEmpty || villageByVillage.isNotEmpty;

  UnreadCounts copyClearDm(String roomId) {
    final m = Map<String, int>.from(dmByRoom)..remove(roomId);
    return UnreadCounts(dmByRoom: m, villageByVillage: villageByVillage);
  }

  UnreadCounts copyClearVillage(String villageId) {
    final m = Map<String, int>.from(villageByVillage)..remove(villageId);
    return UnreadCounts(dmByRoom: dmByRoom, villageByVillage: m);
  }
}

/// 안읽은 메시지 추적 서비스
class UnreadService {
  UnreadService._();
  static final UnreadService instance = UnreadService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// 안읽은 카운트 조회 (한 번에 모든 채널)
  Future<UnreadCounts> fetchCounts() async {
    try {
      final result = await _supabase.rpc('get_unread_counts');
      final dmMap = <String, int>{};
      final villageMap = <String, int>{};

      if (result is List) {
        for (final row in result) {
          if (row is! Map) continue;
          final type = row['channel_type'] as String?;
          final id = row['channel_id'] as String?;
          final count = (row['unread_count'] as num?)?.toInt() ?? 0;
          if (type == null || id == null || count <= 0) continue;

          if (type == 'dm') {
            dmMap[id] = count;
          } else if (type == 'village') {
            villageMap[id] = count;
          }
        }
      }

      return UnreadCounts(
        dmByRoom: dmMap,
        villageByVillage: villageMap,
      );
    } catch (e) {
      print('[UNREAD] 조회 실패: $e');
      return const UnreadCounts();
    }
  }

  /// 특정 채널을 읽음으로 마킹
  Future<void> markRead({
    required String channelType,
    required String channelId,
  }) async {
    try {
      await _supabase.rpc('mark_channel_read', params: {
        'p_channel_type': channelType,
        'p_channel_id': channelId,
      });
    } catch (e) {
      print('[UNREAD] 읽음 마킹 실패: $e');
    }
  }

  Future<void> markDmRead(String roomId) =>
      markRead(channelType: 'dm', channelId: roomId);

  Future<void> markVillageRead(String villageId) =>
      markRead(channelType: 'village', channelId: villageId);
}

/// 전역 안읽은 카운트 Notifier
///
/// 사용 패턴:
/// - 앱 시작 시 자동으로 fetch
/// - 채팅방 진입 시 markRead + refresh
/// - 새 메시지 broadcast 받으면 refresh (선택)
class UnreadCountsNotifier extends Notifier<UnreadCounts> {
  @override
  UnreadCounts build() {
    // 백그라운드로 초기 fetch
    Future.microtask(refresh);
    return const UnreadCounts();
  }

  Future<void> refresh() async {
    final counts = await UnreadService.instance.fetchCounts();
    state = counts;
  }

  /// DM 방 진입 시 호출 — 즉시 클리어 + 서버 마킹
  Future<void> markDmRead(String roomId) async {
    // 낙관적으로 즉시 클리어
    state = state.copyClearDm(roomId);
    await UnreadService.instance.markDmRead(roomId);
  }

  /// 마을 채팅 진입 시 호출
  Future<void> markVillageRead(String villageId) async {
    state = state.copyClearVillage(villageId);
    await UnreadService.instance.markVillageRead(villageId);
  }
}

final unreadCountsProvider =
    NotifierProvider<UnreadCountsNotifier, UnreadCounts>(
  UnreadCountsNotifier.new,
);

final unreadServiceProvider = Provider<UnreadService>((ref) {
  return UnreadService.instance;
});