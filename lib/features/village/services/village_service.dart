import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/safety_service.dart';
import '../models/village.dart';

/// 마을 관련 데이터 서비스
class VillageService {
  VillageService._();
  static final VillageService instance = VillageService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  // ===========================================================
  // 조회
  // ===========================================================

  /// 내가 가입한 마을 id 집합
  Future<Set<String>> fetchMyVillageIds() async {
    final rows = await _supabase
        .from('village_members')
        .select('village_id')
        .eq('user_id', _uid);
    return rows.map((r) => r['village_id'] as String).toSet();
  }

  /// 탐색 목록 (카테고리/검색어 필터, 멤버 많은 순)
  /// 각 마을에 isJoined를 채워서 반환한다.
  Future<List<Village>> fetchExploreVillages({
    String? category,
    String? search,
  }) async {
    var query = _supabase.from('villages').select();

    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('name', '%${search.trim()}%');
    }

    final rows = await query
        .order('member_count', ascending: false)
        .order('created_at', ascending: false)
        .limit(50);

    final myIds = await fetchMyVillageIds();

    return rows
        .map((r) => Village.fromJson(r, isJoined: myIds.contains(r['id'])))
        .toList();
  }

  /// 내가 가입한 마을 목록 (최근 가입 순)
  Future<List<Village>> fetchMyVillages() async {
    final rows = await _supabase
        .from('village_members')
        .select('joined_at, villages(*)')
        .eq('user_id', _uid)
        .order('joined_at', ascending: false);

    return rows
        .where((r) => r['villages'] != null)
        .map((r) => Village.fromJson(
              r['villages'] as Map<String, dynamic>,
              isJoined: true,
            ))
        .toList();
  }

  /// 마을 단건 조회
  Future<Village> fetchVillage(String villageId) async {
    final row = await _supabase
        .from('villages')
        .select()
        .eq('id', villageId)
        .single();

    final myIds = await fetchMyVillageIds();
    return Village.fromJson(row, isJoined: myIds.contains(villageId));
  }

  /// 마을 멤버 목록 (오너 먼저, 그다음 가입 순)
  Future<List<VillageMember>> fetchMembers(String villageId) async {
    final rows = await _supabase
        .from('village_members')
        .select('user_id, role, joined_at, profiles(nickname, avatar_url)')
        .eq('village_id', villageId)
        .order('joined_at', ascending: true);

    final blockedIds = await SafetyService.instance.fetchBlockedIds();
    final members = rows
        .map(VillageMember.fromJson)
        .where((m) => !blockedIds.contains(m.userId))
        .toList();
    members.sort((a, b) {
      if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
      return a.joinedAt.compareTo(b.joinedAt);
    });
    return members;
  }

  // ===========================================================
  // 생성 / 가입 / 탈퇴
  // ===========================================================

  /// 마을 생성. 오너 멤버 등록은 DB 트리거(auto_join_owner)가 처리한다.
  Future<Village> createVillage({
    required String name,
    required String category,
    String? description,
    int maxMembers = 100,
  }) async {
    final row = await _supabase
        .from('villages')
        .insert({
          'name': name.trim(),
          'description': description?.trim(),
          'category': category,
          'owner_id': _uid,
          'max_members': maxMembers,
        })
        .select()
        .single();

    print('[VILLAGE] 마을 생성: ${row['id']} (${row['name']})');
    return Village.fromJson(row, isJoined: true);
  }

  /// 마을 가입
  Future<void> joinVillage(String villageId) async {
    await _supabase.from('village_members').insert({
      'village_id': villageId,
      'user_id': _uid,
    });
    print('[VILLAGE] 가입: $villageId');
  }

  /// 마을 탈퇴 (오너는 탈퇴 불가 - 호출 전에 UI에서 막는다)
  Future<void> leaveVillage(String villageId) async {
    await _supabase
        .from('village_members')
        .delete()
        .eq('village_id', villageId)
        .eq('user_id', _uid);
    print('[VILLAGE] 탈퇴: $villageId');
  }

  /// 마을 삭제 (오너 전용)
  Future<void> deleteVillage(String villageId) async {
    await _supabase.from('villages').delete().eq('id', villageId);
    print('[VILLAGE] 삭제: $villageId');
  }
}

/// 서비스 프로바이더
final villageServiceProvider = Provider<VillageService>((ref) {
  return VillageService.instance;
});

/// 내 마을 목록 (내 마을 탭에서 watch, 가입/탈퇴/생성 후 invalidate)
class MyVillagesNotifier extends AsyncNotifier<List<Village>> {
  @override
  Future<List<Village>> build() {
    return VillageService.instance.fetchMyVillages();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => VillageService.instance.fetchMyVillages(),
    );
  }
}

final myVillagesProvider =
    AsyncNotifierProvider<MyVillagesNotifier, List<Village>>(
  MyVillagesNotifier.new,
);