// 교랑빌리지 푸시 알림 발송 Edge Function
//
// 호출 방법 (DB 트리거에서 pg_net으로 호출):
//   POST {SUPABASE_URL}/functions/v1/send-notification
//   Body: { user_id, type, title, body, data }
//
// 동작:
//   1. 받는 사람의 fcm_token + notification_settings 조회
//   2. 해당 type 알림이 활성화돼 있는지 확인
//   3. Google OAuth2 access token 발급 (서비스 계정 JWT 서명)
//   4. FCM v1 API로 푸시 발송
//
// 환경변수:
//   FIREBASE_PROJECT_ID
//   FIREBASE_CLIENT_EMAIL
//   FIREBASE_PRIVATE_KEY  (멀티라인, \n 포함)
//
// 배포:
//   supabase functions deploy send-notification --project-ref kyadyqbdugpemzimouxr

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SignJWT, importPKCS8 } from 'https://esm.sh/jose@5';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type NotificationType =
  | 'dm'
  | 'friend_request'
  | 'mention'
  | 'post_comment'
  | 'comment_reply'
  | 'village_chat';

interface NotificationPayload {
  user_id: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, string>;
}

// type → notification_settings 컬럼 매핑
const TYPE_TO_COLUMN: Record<NotificationType, string> = {
  dm: 'dm_enabled',
  friend_request: 'friend_request_enabled',
  mention: 'mention_enabled',
  post_comment: 'post_comment_enabled',
  comment_reply: 'comment_reply_enabled',
  village_chat: 'village_chat_enabled',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const payload = (await req.json()) as NotificationPayload;
    const { user_id, type, title, body, data } = payload;

    if (!user_id || !type || !title || !body) {
      return json({ error: '필수 필드 누락' }, 400);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // 1. 받는 사람의 fcm_token + 알림 설정 조회
    const { data: profile } = await admin
      .from('profiles')
      .select('fcm_token, is_banned')
      .eq('id', user_id)
      .maybeSingle();

    if (!profile?.fcm_token) {
      return json({ skipped: 'no_token' });
    }
    if (profile.is_banned) {
      return json({ skipped: 'banned' });
    }

    // 알림 설정 확인
    const { data: settings } = await admin
      .from('notification_settings')
      .select('*')
      .eq('user_id', user_id)
      .maybeSingle();

    const column = TYPE_TO_COLUMN[type];
    // 설정 행이 없으면 기본값으로 처리 (village_chat은 false, 나머지는 true)
    const enabled = settings
      ? (settings as Record<string, boolean>)[column] === true
      : type !== 'village_chat';

    if (!enabled) {
      return json({ skipped: 'disabled' });
    }

    // 2. FCM access token 발급
    const accessToken = await getFcmAccessToken();
    if (!accessToken) {
      return json({ error: 'FCM access token 발급 실패' }, 500);
    }

    // 3. FCM v1 API 호출
    const projectId = Deno.env.get('FIREBASE_PROJECT_ID')!;
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const fcmBody = {
      message: {
        token: profile.fcm_token,
        notification: { title, body },
        data: {
          type,
          ...(data ?? {}),
        },
        android: {
          priority: 'HIGH',
          notification: {
            channel_id: 'kyorang_village_default',
            sound: 'default',
          },
        },
      },
    };

    const fcmRes = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fcmBody),
    });

    if (!fcmRes.ok) {
      const errText = await fcmRes.text();
      console.error(
        `[SEND_NOTI] FCM ${fcmRes.status}:`,
        errText.substring(0, 500),
      );

      // 토큰 무효 (UNREGISTERED, INVALID_ARGUMENT 등) → 토큰 정리
      if (
        fcmRes.status === 404 ||
        errText.includes('UNREGISTERED') ||
        errText.includes('INVALID_ARGUMENT')
      ) {
        await admin
          .from('profiles')
          .update({ fcm_token: null })
          .eq('id', user_id);
        return json({ skipped: 'invalid_token', cleared: true });
      }

      return json({ error: 'FCM 발송 실패', detail: errText }, 500);
    }

    return json({ ok: true });
  } catch (e) {
    console.error('[SEND_NOTI] 예외:', e);
    return json({ error: '서버 오류', detail: String(e) }, 500);
  }
});

// ===========================================================
// Google OAuth2 access token 발급 (FCM v1 API용)
// ===========================================================

// 토큰 캐시 (Edge Function 인스턴스 내에서만 유효)
let cachedToken: { value: string; expiresAt: number } | null = null;

async function getFcmAccessToken(): Promise<string | null> {
  // 캐시된 토큰이 5분 이상 남아있으면 재사용
  if (cachedToken && cachedToken.expiresAt > Date.now() + 5 * 60 * 1000) {
    return cachedToken.value;
  }

  try {
    const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL')!;
    let privateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')!;

    // 환경변수에 \n이 리터럴 문자열로 들어가는 경우가 있어 실제 줄바꿈으로 변환
    privateKey = privateKey.replace(/\\n/g, '\n');

    const key = await importPKCS8(privateKey, 'RS256');
    const now = Math.floor(Date.now() / 1000);

    const jwt = await new SignJWT({
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
    })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(clientEmail)
      .setSubject(clientEmail)
      .setAudience('https://oauth2.googleapis.com/token')
      .setIssuedAt(now)
      .setExpirationTime(now + 3600)
      .sign(key);

    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error('[SEND_NOTI] OAuth ${res.status}:', errText);
      return null;
    }

    const tokenData = await res.json();
    const accessToken = tokenData.access_token as string;
    const expiresIn = (tokenData.expires_in as number) ?? 3600;

    cachedToken = {
      value: accessToken,
      expiresAt: Date.now() + expiresIn * 1000,
    };

    return accessToken;
  } catch (e) {
    console.error('[SEND_NOTI] access token 발급 예외:', e);
    return null;
  }
}

function json(body: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}