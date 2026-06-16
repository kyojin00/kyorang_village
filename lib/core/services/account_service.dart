import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 회원 탈퇴 관련 서비스
/// 실제 계정 삭제는 Supabase Edge Function 'delete-account'가 수행한다.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// 현재 로그인된 계정을 영구 삭제한다.
  /// 성공 시 Supabase 세션도 자동 만료되므로 호출 직후 로그인 화면으로 보내야 한다.
  Future<void> deleteAccount() async {
    final response = await _supabase.functions.invoke('delete-account');

    if (response.status != 200) {
      final data = response.data;
      final message = (data is Map && data['error'] is String)
          ? data['error'] as String
          : '계정 삭제에 실패했어요.';
      print('[ACCOUNT] 탈퇴 실패: ${response.status} $message');
      throw Exception(message);
    }

    print('[ACCOUNT] 탈퇴 완료');

    // 로컬 세션 정리 (서버는 이미 유저가 사라진 상태)
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      // 이미 유저가 없어서 signOut이 실패할 수 있음 - 무시
      print('[ACCOUNT] 세션 정리 시 예외 (무시): $e');
    }
  }
}

final accountServiceProvider = Provider<AccountService>((ref) {
  return AccountService.instance;
});