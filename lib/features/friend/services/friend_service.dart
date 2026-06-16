import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';

/// 친구 신청 결과
enum FriendRequestResult {
  sent('친구 신청을 보냈어요!'),
  autoAccepted('상대도 신청한 상태라 바로 친구가 됐어요!'),
  alreadyFriends('이미 친구예요.'),
  alreadyRequested('이미 신청한 상태예요. 수락을 기다려 주세요.');

  const FriendRequestResult(this.message);
  final String message;
}

/// 친구 관계 서비스
class FriendService {
  FriendService._();
  static final FriendService instance = FriendService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// friendships ↔ profiles 셀프 관계 2개 → FK 별칭 필수
  static const String _select = '*, '
      'requester:profiles!friendships_requester_id_fkey(nickname, avatar_url), '
      'addressee:profiles!friendships_addressee_id_fkey(nickname, avatar_url)';

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  // ===========================================================
  // 조회
  // ===========================================================

  /// 내 친구 목록 (accepted)
  Future<List<Friendship>> fetchFriends() async {
    final rows = await _supabase
        .from('friendships')
        .select(_select)
        .or('requester_id.eq.$_uid,addressee_id.eq.$_uid')
        .eq('status', 'accepted')
        .order('created_at', ascending: false);

    return rows.map((r) => Friendship.fromJson(r, _uid)).toList();
  }

  /// 내가 받은 신청 (pending)
  Future<List<Friendship>> fetchReceivedRequests() async {
    final rows = await _supabase
        .from('friendships')
        .select(_select)
        .eq('addressee_id', _uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return rows.map((r) => Friendship.fromJson(r, _uid)).toList();
  }

  /// 내가 보낸 신청 (pending)
  Future<List<Friendship>> fetchSentRequests() async {
    final rows = await _supabase
        .from('friendships')
        .select(_select)
        .eq('requester_id', _uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return rows.map((r) => Friendship.fromJson(r, _uid)).toList();
  }

  /// 특정 유저와의 관계 조회 (방향 무관, 없으면 null)
  Future<Friendship?> getRelationWith(String otherUserId) async {
    final rows = await _supabase
        .from('friendships')
        .select(_select)
        .or('and(requester_id.eq.$_uid,addressee_id.eq.$otherUserId),'
            'and(requester_id.eq.$otherUserId,addressee_id.eq.$_uid)')
        .limit(1);

    if (rows.isEmpty) return null;
    return Friendship.fromJson(rows.first, _uid);
  }

  // ===========================================================
  // 신청 / 수락 / 거절 / 끊기
  // ===========================================================

  /// 친구 신청.
  /// 이미 관계가 있으면 상황에 맞게 처리한다:
  /// - 이미 친구 → alreadyFriends
  /// - 내가 이미 신청함 → alreadyRequested
  /// - 상대가 먼저 신청해둔 상태 → 자동 수락 (autoAccepted)
  Future<FriendRequestResult> sendRequest(String otherUserId) async {
    final existing = await getRelationWith(otherUserId);

    if (existing != null) {
      if (existing.isAccepted) return FriendRequestResult.alreadyFriends;
      if (existing.sentByMe(_uid)) {
        return FriendRequestResult.alreadyRequested;
      }
      // 상대가 먼저 신청한 상태 → 수락 처리
      await acceptRequest(existing.id);
      return FriendRequestResult.autoAccepted;
    }

    await _supabase.from('friendships').insert({
      'requester_id': _uid,
      'addressee_id': otherUserId,
      'status': 'pending',
    });
    print('[FRIEND] 신청: $otherUserId');
    return FriendRequestResult.sent;
  }

  /// 신청 수락 (받은 사람만 가능 - RLS로도 강제됨)
  Future<void> acceptRequest(String friendshipId) async {
    await _supabase
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('id', friendshipId);
    print('[FRIEND] 수락: $friendshipId');
  }

  /// 신청 거절 / 신청 취소 / 친구 끊기 (모두 row 삭제)
  Future<void> removeFriendship(String friendshipId) async {
    await _supabase.from('friendships').delete().eq('id', friendshipId);
    print('[FRIEND] 관계 삭제: $friendshipId');
  }
}

final friendServiceProvider = Provider<FriendService>((ref) {
  return FriendService.instance;
});

/// 받은 친구 신청 수 (채팅 탭 배지용)
class ReceivedRequestCount extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final requests = await FriendService.instance.fetchReceivedRequests();
    return requests.length;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final requests =
          await FriendService.instance.fetchReceivedRequests();
      return requests.length;
    });
  }
}

final receivedRequestCountProvider =
    AsyncNotifierProvider<ReceivedRequestCount, int>(
  ReceivedRequestCount.new,
);