import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/challenge.dart';

/// 챌린지 데이터 서비스
///
/// challenges ↔ profiles는 challenge_participants를 경유하는 다대다 관계가
/// 함께 존재하므로, profiles 조인은 반드시 FK를 명시한다 (PGRST201 방지).
class ChallengeService {
  ChallengeService._();
  static final ChallengeService instance = ChallengeService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  /// 'yyyy-MM-dd' (date 컬럼용)
  String _dateString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _today => _dateString(DateTime.now());

  // ===========================================================
  // 조회
  // ===========================================================

  /// 마을 챌린지 목록 (최신순)
  /// 참가자 수 / 내 참가 여부 / 내 인증 수 / 오늘 인증 여부를 채워서 반환.
  /// 쿼리 3번 고정: 챌린지 + 참가자 전체 + 내 인증 전체
  Future<List<Challenge>> fetchChallenges(String villageId) async {
    final rows = await _supabase
        .from('challenges')
        .select()
        .eq('village_id', villageId)
        .order('created_at', ascending: false);

    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r['id'] as String).toList();

    // 참가자 (카운트 + 내 참가 여부)
    final participantRows = await _supabase
        .from('challenge_participants')
        .select('challenge_id, user_id')
        .inFilter('challenge_id', ids);

    final countMap = <String, int>{};
    final myJoined = <String>{};
    for (final p in participantRows) {
      final cid = p['challenge_id'] as String;
      countMap[cid] = (countMap[cid] ?? 0) + 1;
      if (p['user_id'] == _uid) myJoined.add(cid);
    }

    // 내 인증 (개수 + 오늘 인증 여부)
    final myCheckinRows = await _supabase
        .from('challenge_checkins')
        .select('challenge_id, checkin_date')
        .eq('user_id', _uid)
        .inFilter('challenge_id', ids);

    final myCheckinCount = <String, int>{};
    final checkedToday = <String>{};
    for (final c in myCheckinRows) {
      final cid = c['challenge_id'] as String;
      myCheckinCount[cid] = (myCheckinCount[cid] ?? 0) + 1;
      if (c['checkin_date'] == _today) checkedToday.add(cid);
    }

    return rows.map((r) {
      final id = r['id'] as String;
      return Challenge.fromJson(
        r,
        participantCount: countMap[id] ?? 0,
        isParticipating: myJoined.contains(id),
        myCheckinCount: myCheckinCount[id] ?? 0,
        hasCheckedInToday: checkedToday.contains(id),
      );
    }).toList();
  }

  /// 챌린지 단건 갱신
  Future<Challenge> fetchChallenge(String challengeId) async {
    final row = await _supabase
        .from('challenges')
        .select()
        .eq('id', challengeId)
        .single();

    final participantRows = await _supabase
        .from('challenge_participants')
        .select('user_id')
        .eq('challenge_id', challengeId);

    final myCheckinRows = await _supabase
        .from('challenge_checkins')
        .select('checkin_date')
        .eq('challenge_id', challengeId)
        .eq('user_id', _uid);

    return Challenge.fromJson(
      row,
      participantCount: participantRows.length,
      isParticipating:
          participantRows.any((p) => p['user_id'] == _uid),
      myCheckinCount: myCheckinRows.length,
      hasCheckedInToday:
          myCheckinRows.any((c) => c['checkin_date'] == _today),
    );
  }

  /// 인증 피드 (최신순)
  Future<List<ChallengeCheckin>> fetchCheckins(String challengeId) async {
    final rows = await _supabase
        .from('challenge_checkins')
        .select(
            '*, profiles!challenge_checkins_user_id_fkey(nickname, avatar_url)')
        .eq('challenge_id', challengeId)
        .order('created_at', ascending: false)
        .limit(100);

    return rows.map(ChallengeCheckin.fromJson).toList();
  }

  // ===========================================================
  // 생성 / 참가 / 탈퇴 / 삭제
  // ===========================================================

  /// 챌린지 생성 (생성자는 자동 참가)
  Future<Challenge> createChallenge({
    required String villageId,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    String? description,
  }) async {
    final row = await _supabase
        .from('challenges')
        .insert({
          'village_id': villageId,
          'creator_id': _uid,
          'title': title.trim(),
          'description': description?.trim(),
          'start_date': _dateString(startDate),
          'end_date': _dateString(endDate),
        })
        .select()
        .single();

    final challengeId = row['id'] as String;

    // 생성자 자동 참가
    await _supabase.from('challenge_participants').insert({
      'challenge_id': challengeId,
      'user_id': _uid,
    });

    print('[CHALLENGE] 생성: $challengeId ($title)');
    return Challenge.fromJson(
      row,
      participantCount: 1,
      isParticipating: true,
    );
  }

  Future<void> joinChallenge(String challengeId) async {
    await _supabase.from('challenge_participants').insert({
      'challenge_id': challengeId,
      'user_id': _uid,
    });
    print('[CHALLENGE] 참가: $challengeId');
  }

  Future<void> leaveChallenge(String challengeId) async {
    await _supabase
        .from('challenge_participants')
        .delete()
        .eq('challenge_id', challengeId)
        .eq('user_id', _uid);
    print('[CHALLENGE] 참가 취소: $challengeId');
  }

  Future<void> deleteChallenge(String challengeId) async {
    await _supabase.from('challenges').delete().eq('id', challengeId);
    print('[CHALLENGE] 삭제: $challengeId');
  }

  // ===========================================================
  // 인증
  // ===========================================================

  /// 오늘 인증 추가. 이미 오늘 인증했으면 false 반환.
  Future<ChallengeCheckin?> addCheckin({
    required String challengeId,
    String? content,
    String? imageUrl,
  }) async {
    try {
      final row = await _supabase
          .from('challenge_checkins')
          .insert({
            'challenge_id': challengeId,
            'user_id': _uid,
            'content': content?.trim(),
            'image_url': imageUrl,
            // DB 기본값 current_date는 UTC 기준이라 KST 자정~오전 9시에
            // 어제 날짜로 기록된다. 항상 로컬 날짜를 명시적으로 보낸다.
            'checkin_date': _today,
          })
          .select(
              '*, profiles!challenge_checkins_user_id_fkey(nickname, avatar_url)')
          .single();

      print('[CHALLENGE] 인증 완료: $challengeId');
      return ChallengeCheckin.fromJson(row);
    } on PostgrestException catch (e) {
      // unique (challenge_id, user_id, checkin_date) 위반 = 오늘 이미 인증
      if (e.code == '23505') {
        print('[CHALLENGE] 오늘 이미 인증함: $challengeId');
        return null;
      }
      rethrow;
    }
  }

  Future<void> deleteCheckin(String checkinId) async {
    await _supabase
        .from('challenge_checkins')
        .delete()
        .eq('id', checkinId);
    print('[CHALLENGE] 인증 삭제: $checkinId');
  }
}

final challengeServiceProvider = Provider<ChallengeService>((ref) {
  return ChallengeService.instance;
});