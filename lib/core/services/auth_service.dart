import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 교랑빌리지 인증 서비스
///
/// 정책: 휴대폰 인증이 마스터. Google/이메일은 가입 후 연결하는 편의 수단.
///
/// 흐름:
/// 1. 신규/기존 로그인: Firebase Phone Auth → OTP → Supabase 로그인
///    (가짜 이메일 {phone}@phone.kyorang.com + 결정적 비밀번호)
/// 2. Google/이메일 연결: 마이 탭에서 linkIdentity 호출
/// 3. 연결 후엔 Google/이메일로도 로그인 가능 (Supabase가 자동 식별)
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final fb.FirebaseAuth _firebaseAuth = fb.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  // ===========================================================
  // 전화번호 정규화
  // ===========================================================

  String cleanPhone(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String toE164(String input) {
    final clean = cleanPhone(input);
    if (clean.startsWith('010')) {
      return '+82${clean.substring(1)}';
    }
    return '+82$clean';
  }

  // ===========================================================
  // 1단계: OTP 발송 (기존 그대로)
  // ===========================================================

  Future<void> sendOtp({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(AuthResult result) onAutoVerified,
    required void Function(String message) onError,
  }) async {
    final clean = cleanPhone(phone);

    if (!RegExp(r'^010\d{8}$').hasMatch(clean)) {
      onError('올바른 휴대폰 번호를 입력해 주세요.');
      return;
    }

    try {
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: toE164(clean),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          try {
            await _firebaseAuth.signInWithCredential(credential);
            final isNew = await _loginToSupabase(clean);
            onAutoVerified(
                isNew ? AuthResult.signedUp : AuthResult.signedIn);
          } catch (e) {
            print('[AUTH] 자동 인증 후 로그인 실패: $e');
            onError('자동 인증에 실패했어요. 인증번호를 직접 입력해 주세요.');
          }
        },
        verificationFailed: (e) {
          print('[AUTH] OTP 발송 실패: ${e.code} ${e.message}');
          onError(_firebaseErrorMessage(e));
        },
        codeSent: (verificationId, resendToken) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) {},
      );
    } catch (e) {
      print('[AUTH] sendOtp 예외: $e');
      onError('인증번호 발송 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  // ===========================================================
  // 2단계: OTP 검증 + Supabase 로그인 (기존 그대로)
  // ===========================================================

  /// OTP 검증 후 Supabase 로그인까지 완료한다.
  /// 성공 시 신규/기존 여부를 반환. 실패 시 null + [onError] 호출.
  Future<AuthResult?> verifyOtp({
    required String phone,
    required String verificationId,
    required String smsCode,
    required void Function(String message) onError,
  }) async {
    final clean = cleanPhone(phone);

    try {
      final credential = fb.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      await _firebaseAuth.signInWithCredential(credential);
    } on fb.FirebaseAuthException catch (e) {
      print('[AUTH] OTP 검증 실패: ${e.code}');
      onError(_firebaseErrorMessage(e));
      return null;
    } catch (e) {
      print('[AUTH] OTP 검증 예외: $e');
      onError('인증에 실패했어요. 다시 시도해 주세요.');
      return null;
    }

    try {
      final isNew = await _loginToSupabase(clean);
      return isNew ? AuthResult.signedUp : AuthResult.signedIn;
    } catch (e) {
      print('[AUTH] Supabase 로그인 실패: $e');
      onError('로그인 처리 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.');
      return null;
    }
  }

  // ===========================================================
  // Supabase 로그인 (없으면 가입) - 기존 그대로
  // ===========================================================

  /// Edge Function `phone-login`을 통해 Supabase 세션을 발급받는다.
  ///
  /// 흐름:
  ///   1. Firebase ID Token 획득
  ///   2. phone-login 함수 호출 (phone + id_token)
  ///   3. 함수가 user 찾기/생성 + 임의 비번 발급
  ///   4. 받은 email + password로 signInWithPassword
  ///
  /// 반환: 신규 가입 여부
  Future<bool> _loginToSupabase(String clean) async {
    final fbUser = _firebaseAuth.currentUser;
    if (fbUser == null) {
      throw Exception('Firebase 인증이 완료되지 않았어요.');
    }

    final idToken = await fbUser.getIdToken();
    if (idToken == null) {
      throw Exception('Firebase ID Token을 받지 못했어요.');
    }

    final res = await _supabase.functions.invoke(
      'phone-login',
      body: {'phone': clean, 'id_token': idToken},
    );

    if (res.status != 200 || res.data is! Map) {
      print('[AUTH] phone-login 실패: status=${res.status}, data=${res.data}');
      throw Exception('로그인 처리에 실패했어요.');
    }

    final data = res.data as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error']?.toString() ?? '로그인 실패');
    }

    final email = data['email'] as String;
    final password = data['password'] as String;
    final isNew = data['is_new'] as bool? ?? false;

    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    print('[AUTH] Supabase 로그인 성공: $email (is_new=$isNew)');
    return isNew;
  }

  // ===========================================================
  // Identity 관리 (Google · 이메일 연결/해제)
  // ===========================================================

  /// 현재 사용자에게 연결된 identity 목록
  /// (email/phone, google 등)
  List<UserIdentity> get currentIdentities {
    return _supabase.auth.currentUser?.identities ?? [];
  }

  /// 연결된 Google 계정 이메일 (있으면)
  String? get linkedGoogleEmail {
    for (final i in currentIdentities) {
      if (i.provider == 'google') {
        return i.identityData?['email'] as String?;
      }
    }
    return null;
  }

  /// Google identity 연결.
  /// Supabase가 OAuth 흐름을 자동 시작 → 성공 시 현재 user에 identity 추가.
  Future<bool> linkGoogle() async {
    try {
      final ok = await _supabase.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: 'io.supabase.kyorangvillage://login-callback',
      );
      print('[AUTH] Google 연결 시작: $ok');
      return ok;
    } catch (e) {
      print('[AUTH] Google 연결 실패: $e');
      rethrow;
    }
  }

  /// identity 연결 해제 (예: Google 연결 끊기)
  /// 마지막 남은 identity는 해제할 수 없음 (Supabase가 막음)
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
  // 전화번호 변경
  // ===========================================================

  /// 새 전화번호로 OTP 발송. 변경 흐름은 일반 sendOtp와 동일하지만,
  /// 호출자가 검증 후 [confirmPhoneChange]를 호출해야 함.
  Future<void> sendPhoneChangeOtp({
    required String newPhone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    final clean = cleanPhone(newPhone);
    if (!RegExp(r'^010\d{8}$').hasMatch(clean)) {
      onError('올바른 휴대폰 번호를 입력해 주세요.');
      return;
    }

    // 새 번호가 이미 다른 계정에 등록돼 있는지 확인
    final existing = await _supabase
        .from('profiles')
        .select('id')
        .eq('phone', clean)
        .maybeSingle();
    if (existing != null && existing['id'] != currentUserId) {
      onError('이 번호는 이미 다른 계정이 사용 중이에요.');
      return;
    }

    try {
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: toE164(clean),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (_) {
          // 변경 흐름에서는 자동 인증을 처리하지 않음 (사용자 확인 필요)
        },
        verificationFailed: (e) {
          onError(_firebaseErrorMessage(e));
        },
        codeSent: (verificationId, _) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      print('[AUTH] 전화번호 변경 OTP 발송 예외: $e');
      onError('인증번호 발송 중 오류가 발생했어요.');
    }
  }

  /// 새 전화번호 OTP 확인 후 변경 적용.
  /// Firebase에서 새 번호로 자격 증명 검증 → profiles.phone 업데이트 +
  /// auth.users.email을 새 가짜 이메일로 업데이트.
  Future<bool> confirmPhoneChange({
    required String newPhone,
    required String verificationId,
    required String smsCode,
    required void Function(String message) onError,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      onError('로그인 정보가 없어요.');
      return false;
    }

    final clean = cleanPhone(newPhone);

    // Firebase에서 새 번호 자격 검증
    try {
      final credential = fb.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      // signInWithCredential는 세션을 갈아치우므로 사용하지 않음.
      // 검증만 위해 credential 객체로 검증 시도하는 정식 API는 없음 →
      // Firebase 측 검증은 signInWithCredential 후 다시 원래 세션으로
      // 돌아오는 방식 사용. 다만 우리 인증은 Supabase 세션이 기준이므로
      // Firebase signOut만 하고 Supabase 세션은 유지된다.
      await _firebaseAuth.signInWithCredential(credential);
      await _firebaseAuth.signOut(); // Firebase 세션은 즉시 정리
    } on fb.FirebaseAuthException catch (e) {
      onError(_firebaseErrorMessage(e));
      return false;
    } catch (e) {
      print('[AUTH] 새 번호 검증 예외: $e');
      onError('인증에 실패했어요. 다시 시도해 주세요.');
      return false;
    }

    // Supabase 측 업데이트
    try {
      // profiles.phone 갱신
      await _supabase
          .from('profiles')
          .update({'phone': clean})
          .eq('id', uid);

      // user.email은 건드리지 않는다.
      // 이메일이 진짜 이메일로 연결돼 있을 수도 있고, 변경할 필요도 없다.
      // 휴대폰 로그인은 phone-login Edge Function이 phone으로 user를 찾으므로
      // user.email이 무엇이든 정상 동작한다.

      print('[AUTH] 전화번호 변경 완료: $clean');
      return true;
    } catch (e) {
      print('[AUTH] 전화번호 변경 실패: $e');
      onError('변경 처리 중 오류가 발생했어요.');
      return false;
    }
  }

  // ===========================================================
  // Google 로그인 (가입 후 연결한 사용자가 Google로 재로그인)
  // ===========================================================

  /// Google OAuth 로그인.
  /// 이미 같은 Google identity가 연결된 user가 있으면 그 user로 로그인.
  /// 연결된 적 없는 Google이면 새 user가 생성되는데, 우리 정책상 그건 막아야 함.
  /// → Supabase 대시보드의 "Allow new users to sign up" 옵션을 비활성화하면
  ///   연결 안 된 Google은 로그인 자체가 거부됨.
  Future<bool> signInWithGoogle() async {
    try {
      final ok = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.kyorangvillage://login-callback',
      );
      print('[AUTH] Google 로그인 시작: $ok');
      return ok;
    } catch (e) {
      print('[AUTH] Google 로그인 실패: $e');
      rethrow;
    }
  }

  // ===========================================================
  // 세션 / 로그아웃
  // ===========================================================

  Session? get currentSession => _supabase.auth.currentSession;
  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _firebaseAuth.signOut();
  }

  // ===========================================================
  // 에러 메시지 한국어 변환
  // ===========================================================

  String _firebaseErrorMessage(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return '올바르지 않은 전화번호예요.';
      case 'invalid-verification-code':
        return '인증번호가 일치하지 않아요.';
      case 'session-expired':
        return '인증 시간이 만료됐어요. 인증번호를 다시 받아 주세요.';
      case 'too-many-requests':
        return '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.';
      case 'quota-exceeded':
        return '오늘 인증 요청이 너무 많았어요. 내일 다시 시도해 주세요.';
      case 'network-request-failed':
        return '네트워크 연결을 확인해 주세요.';
      default:
        return '인증 중 오류가 발생했어요. (${e.code})';
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});

final isLoggedInProvider = Provider<bool>((ref) {
  return AuthService.instance.currentSession != null;
});

/// 휴대폰 인증 결과
enum AuthResult {
  /// 기존 사용자 로그인
  signedIn,

  /// 신규 가입 → 닉네임 온보딩 필요
  signedUp,
}