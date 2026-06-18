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
  ///
  /// 검색 로직 v1.1:
  /// - 검색어가 카테고리 라벨(예: "운동")과 일치하면 해당 카테고리 코드도 매칭
  /// - 이름 + 설명에 ILIKE로 부분 일치
  /// - 검색 시엔 정확 매치 > 부분 매치 > 인기순으로 정렬
  Future<List<Village>> fetchExploreVillages({
    String? category,
    String? search,
  }) async {
    final trimmedSearch = search?.trim();
    final hasSearch = trimmedSearch != null && trimmedSearch.isNotEmpty;

    var query = _supabase.from('villages').select();

    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }

    if (hasSearch) {
      final escaped = _escapeForIlike(trimmedSearch);

      // 검색어가 카테고리 라벨과 일치하는지 확인
      final matchedCategoryCodes = VillageCategory.all
          .where((c) => c.label.contains(trimmedSearch) ||
              trimmedSearch.contains(c.label))
          .map((c) => c.code)
          .toList();

      // OR 조건 조립
      final orClauses = <String>[
        'name.ilike.%$escaped%',
        'description.ilike.%$escaped%',
      ];
      for (final code in matchedCategoryCodes) {
        orClauses.add('category.eq.$code');
      }

      query = query.or(orClauses.join(','));
    }

    final rows = await query
        .order('member_count', ascending: false)
        .order('created_at', ascending: false)
        .limit(50);

    final myIds = await fetchMyVillageIds();

    var villages = rows
        .map((r) => Village.fromJson(r, isJoined: myIds.contains(r['id'])))
        .toList();

    // 검색 시 클라이언트 측 재정렬:
    // 1. 이름 정확 매치
    // 2. 이름 시작 매치
    // 3. 그 외 (서버 정렬 유지)
    if (hasSearch) {
      final q = trimmedSearch.toLowerCase();
      int rank(Village v) {
        final name = v.name.toLowerCase();
        if (name == q) return 0;
        if (name.startsWith(q)) return 1;
        if (name.contains(q)) return 2;
        return 3;
      }
      villages.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return b.memberCount.compareTo(a.memberCount);
      });
    }

    return villages;
  }

  /// PostgREST or 필터에서 안전하게 쓰이도록 특수문자 이스케이프
  /// (`,` `(` `)`가 들어 있으면 필터 파싱이 깨질 수 있다)
  String _escapeForIlike(String s) {
    return s.replaceAll(',', '\\,').replaceAll('(', '\\(').replaceAll(')', '\\)');
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

  Future<void> joinVillage(String villageId) async {
    await _supabase.from('village_members').insert({
      'village_id': villageId,
      'user_id': _uid,
    });
    print('[VILLAGE] 가입: $villageId');
  }

  Future<void> leaveVillage(String villageId) async {
    await _supabase
        .from('village_members')
        .delete()
        .eq('village_id', villageId)
        .eq('user_id', _uid);
    print('[VILLAGE] 탈퇴: $villageId');
  }

  Future<void> deleteVillage(String villageId) async {
    await _supabase.from('villages').delete().eq('id', villageId);
    print('[VILLAGE] 삭제: $villageId');
  }
}

final villageServiceProvider = Provider<VillageService>((ref) {
  return VillageService.instance;
});

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