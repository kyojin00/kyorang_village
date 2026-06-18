import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 교랑빌리지 인증 서비스 (v1.3)
///
/// 정책: 이메일 + 비밀번호 또는 Google OAuth로 가입/로그인.
/// 이메일 가입 시 Supabase가 확인 메일을 발송 (Console에서 강제 설정됨).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// OAuth 콜백용 deep link
  static const String _oauthRedirect =
      'io.supabase.kyorangvillage://login-callback';

  // ===========================================================
  // 이메일 가입 / 로그인
  // ===========================================================

  /// 이메일 + 비밀번호로 회원가입.
  /// Supabase가 확인 메일을 발송하므로, 사용자가 메일에서 링크 클릭 후
  /// 로그인 가능. 가입 직후엔 session이 null.
  Future<SignUpStatus> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );

    // 사용자 객체가 만들어졌지만 session이 없으면 → 이메일 확인 대기
    if (response.user != null && response.session == null) {
      return SignUpStatus.confirmEmailSent;
    }

    // session이 바로 만들어진 경우 (이메일 확인 비활성 시) — 즉시 가입 완료
    if (response.session != null) {
      return SignUpStatus.signedIn;
    }

    return SignUpStatus.failed;
  }

  /// 이메일 + 비밀번호 로그인
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    print('[AUTH] 이메일 로그인 성공: ${email.trim()}');
  }

  /// 비밀번호 재설정 메일 발송
  Future<void> sendPasswordReset(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: _oauthRedirect,
    );
    print('[AUTH] 비밀번호 재설정 메일 발송: ${email.trim()}');
  }

  /// 확인 메일 재발송
  Future<void> resendConfirmation(String email) async {
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
    );
    print('[AUTH] 확인 메일 재발송: ${email.trim()}');
  }

  // ===========================================================
  // Google OAuth
  // ===========================================================

  /// Google OAuth 로그인/가입.
  /// 신규 사용자도 동일 메서드로 처리 (Supabase가 자동 계정 생성).
  /// 브라우저로 빠져나가고 deep link로 돌아옴 — 화면 측이
  /// onAuthStateChange로 결과 처리.
  Future<bool> signInWithGoogle() async {
    try {
      final ok = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _oauthRedirect,
      );
      print('[AUTH] Google OAuth 시작: $ok');
      return ok;
    } catch (e) {
      print('[AUTH] Google 로그인 실패: $e');
      rethrow;
    }
  }

  // ===========================================================
  // Identity 관리
  // ===========================================================

  List<UserIdentity> get currentIdentities {
    return _supabase.auth.currentUser?.identities ?? [];
  }

  String? get linkedGoogleEmail {
    for (final i in currentIdentities) {
      if (i.provider == 'google') {
        return i.identityData?['email'] as String?;
      }
    }
    return null;
  }

  /// 현재 user에 Google identity 추가 연결
  Future<bool> linkGoogle() async {
    try {
      final ok = await _supabase.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: _oauthRedirect,
      );
      print('[AUTH] Google 연결 시작: $ok');
      return ok;
    } catch (e) {
      print('[AUTH] Google 연결 실패: $e');
      rethrow;
    }
  }

  Future<void> unlinkIdentity(UserIdentity identity) async {
    try {
      await _supabase.auth.unlinkIdentity(identity);
      print('[AUTH] identity 해제: ${identity.provider}');
    } catch (e) {
      print('[AUTH] identity 해제 실패: $e');
      rethrow;
    }
  }

  // ===========================================================
  // 세션 / 로그아웃
  // ===========================================================

  Session? get currentSession => _supabase.auth.currentSession;
  String? get currentUserId => _supabase.auth.currentUser?.id;
  String? get currentEmail => _supabase.auth.currentUser?.email;

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    print('[AUTH] 로그아웃 완료');
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});

final isLoggedInProvider = Provider<bool>((ref) {
  return AuthService.instance.currentSession != null;
});

/// 가입 결과
enum SignUpStatus {
  /// 가입 완료, 확인 메일 발송됨 → 사용자가 메일 확인 후 로그인 필요
  confirmEmailSent,

  /// 가입 즉시 로그인됨 (이메일 확인 비활성 시)
  signedIn,

  /// 실패
  failed,
}