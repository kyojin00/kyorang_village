import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 신고 대상 유형 (reports.target_type)
enum ReportTargetType {
  user('user', '사용자'),
  village('village', '마을'),
  post('post', '게시글'),
  comment('comment', '댓글'),
  message('message', '메시지');

  const ReportTargetType(this.code, this.label);
  final String code;
  final String label;
}

/// 신고 사유 프리셋
enum ReportReason {
  spam('스팸 / 광고'),
  abuse('욕설 / 혐오 발언'),
  sexual('음란성 콘텐츠'),
  fraud('사기 / 사칭'),
  etc('기타');

  const ReportReason(this.label);
  final String label;
}

/// 차단 / 신고 서비스
class SafetyService {
  SafetyService._();
  static final SafetyService instance = SafetyService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// 차단 목록 메모리 캐시 (조회 필터링에서 매번 DB 안 거치도록)
  Set<String>? _blockedCache;

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  // ===========================================================
  // 차단
  // ===========================================================

  /// 내가 차단한 유저 id 집합 (캐시 우선)
  Future<Set<String>> fetchBlockedIds({bool refresh = false}) async {
    if (!refresh && _blockedCache != null) return _blockedCache!;

    final rows = await _supabase
        .from('blocks')
        .select('blocked_id')
        .eq('blocker_id', _uid);

    _blockedCache = rows.map((r) => r['blocked_id'] as String).toSet();
    return _blockedCache!;
  }

  Future<bool> isBlocked(String userId) async {
    final ids = await fetchBlockedIds();
    return ids.contains(userId);
  }

  Future<void> block(String userId) async {
    await _supabase.from('blocks').upsert({
      'blocker_id': _uid,
      'blocked_id': userId,
    });
    _blockedCache?.add(userId);
    print('[SAFETY] 차단: $userId');
  }

  Future<void> unblock(String userId) async {
    await _supabase
        .from('blocks')
        .delete()
        .eq('blocker_id', _uid)
        .eq('blocked_id', userId);
    _blockedCache?.remove(userId);
    print('[SAFETY] 차단 해제: $userId');
  }

  /// 차단한 사람들의 프로필(닉네임·아바타)을 함께 조회.
  /// 차단 관리 화면에서 사용.
  Future<List<BlockedProfile>> fetchBlockedProfiles() async {
    final rows = await _supabase
        .from('blocks')
        .select('blocked_id, created_at, profiles!blocks_blocked_id_fkey(nickname, avatar_url)')
        .eq('blocker_id', _uid)
        .order('created_at', ascending: false);

    return rows.map<BlockedProfile>((r) {
      final profile = r['profiles'] as Map<String, dynamic>?;
      return BlockedProfile(
        userId: r['blocked_id'] as String,
        nickname: profile?['nickname'] as String? ?? '(알 수 없음)',
        avatarUrl: profile?['avatar_url'] as String?,
        blockedAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  /// 로그아웃 등 세션 변경 시 캐시 초기화
  void clearCache() {
    _blockedCache = null;
  }

  // ===========================================================
  // 신고
  // ===========================================================

  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? detail,
  }) async {
    final reasonText = detail != null && detail.trim().isNotEmpty
        ? '${reason.label}: ${detail.trim()}'
        : reason.label;

    await _supabase.from('reports').insert({
      'reporter_id': _uid,
      'target_type': targetType.code,
      'target_id': targetId,
      'reason': reasonText,
    });
    print('[SAFETY] 신고 접수: ${targetType.code}/$targetId');
  }
}

final safetyServiceProvider = Provider<SafetyService>((ref) {
  return SafetyService.instance;
});

/// 차단한 사람 한 명의 정보 (차단 관리 화면용)
class BlockedProfile {
  const BlockedProfile({
    required this.userId,
    required this.nickname,
    required this.blockedAt,
    this.avatarUrl,
  });

  final String userId;
  final String nickname;
  final String? avatarUrl;
  final DateTime blockedAt;
}