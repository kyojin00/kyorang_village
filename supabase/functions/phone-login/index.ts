// 교랑빌리지 휴대폰 로그인 Edge Function (완성)
//
// 흐름:
//   1. 클라이언트가 phone + Firebase ID Token 전송
//   2. Firebase ID Token 검증 (토큰 안 phone과 요청 phone 일치 확인)
//   3. profiles.phone으로 user 찾기. 없으면 새로 만들기 (가짜 이메일 패턴)
//   4. 임의 비밀번호를 생성해 그 user에 설정 후 응답에 포함
//   5. 클라이언트는 응답의 email + password로 즉시 signInWithPassword
//
// 보안:
//   - 1회용 임의 비밀번호. 다음 로그인 시 새로 발급됨
//   - service_role 키는 함수 안에서만 사용. 클라이언트엔 노출 X
//   - HTTPS 전송이라 평문 비밀번호 가로채기 어려움
//
// 배포:
//   supabase functions deploy phone-login --project-ref kyadyqbdugpemzimouxr

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { jwtVerify, createRemoteJWKSet } from 'https://esm.sh/jose@5';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const FIREBASE_ISSUER_PREFIX = 'https://securetoken.google.com/';
const FIREBASE_PROJECT_ID = 'kyorang-talk-3f8a0';

const JWKS = createRemoteJWKSet(new URL(FIREBASE_JWKS_URL));

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const phone = body.phone as string | undefined;
    const idToken = body.id_token as string | undefined;

    if (!phone || !idToken) {
      return json({ error: 'phone과 id_token이 필요합니다.' }, 400);
    }

    // 1. Firebase ID Token 검증
    let tokenPhone: string | null = null;
    try {
      const { payload } = await jwtVerify(idToken, JWKS, {
        issuer: FIREBASE_ISSUER_PREFIX + FIREBASE_PROJECT_ID,
        audience: FIREBASE_PROJECT_ID,
      });
      tokenPhone = (payload.phone_number as string | undefined) ?? null;
    } catch (e) {
      console.error('[PHONE_LOGIN] 토큰 검증 실패:', e);
      return json({ error: '유효하지 않은 인증 토큰입니다.' }, 401);
    }
    if (!tokenPhone) {
      return json({ error: '토큰에 phone_number가 없습니다.' }, 401);
    }

    // 2. phone 일치 확인 (정규화 비교)
    const cleanPhone = phone.replace(/\D/g, '');
    const cleanTokenPhone = tokenPhone.replace(/\D/g, '');
    const normalized = cleanPhone.startsWith('010')
      ? '82' + cleanPhone.substring(1)
      : cleanPhone;
    if (cleanTokenPhone !== normalized) {
      console.error(
        `[PHONE_LOGIN] phone mismatch: req=${cleanPhone}, token=${cleanTokenPhone}`,
      );
      return json({ error: '전화번호가 일치하지 않습니다.' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // 3. profiles.phone으로 user 찾기
    const { data: existingProfile } = await admin
      .from('profiles')
      .select('id')
      .eq('phone', cleanPhone)
      .maybeSingle();

    let userId: string;
    let userEmail: string;
    let isNew = false;

    if (existingProfile) {
      userId = existingProfile.id as string;
      // 기존 user의 현재 이메일 조회 (가짜 이메일일 수도, 진짜 이메일일 수도)
      const { data: userInfo, error: getError } =
        await admin.auth.admin.getUserById(userId);
      if (getError || !userInfo?.user?.email) {
        console.error('[PHONE_LOGIN] user 정보 조회 실패:', getError);
        return json({ error: '계정 정보 조회 실패' }, 500);
      }
      userEmail = userInfo.user.email;
    } else {
      // 새 user 생성
      const fakeEmail = `${cleanPhone}@phone.kyorang.com`;
      const { data: created, error: createError } =
        await admin.auth.admin.createUser({
          email: fakeEmail,
          email_confirm: true,
          user_metadata: { phone: cleanPhone },
        });
      if (createError || !created.user) {
        console.error('[PHONE_LOGIN] createUser 실패:', createError);
        return json({ error: '계정 생성 실패' }, 500);
      }
      userId = created.user.id;
      userEmail = fakeEmail;
      isNew = true;
    }

    // 4. 임의 비밀번호 생성 + user에 설정
    const password = generatePassword();
    const { error: updateError } = await admin.auth.admin.updateUserById(
      userId,
      { password },
    );
    if (updateError) {
      console.error('[PHONE_LOGIN] 비밀번호 갱신 실패:', updateError);
      return json({ error: '세션 발급 실패' }, 500);
    }

    // 5. 응답: 클라이언트가 이 email/password로 signInWithPassword 호출
    return json({
      ok: true,
      email: userEmail,
      password,
      is_new: isNew,
    });
  } catch (e) {
    console.error('[PHONE_LOGIN] 예외:', e);
    return json({ error: '서버 오류', detail: String(e) }, 500);
  }
});

function generatePassword(): string {
  // 32바이트 랜덤 → base64로 약 43자
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes));
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}