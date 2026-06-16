// 교랑빌리지 회원 탈퇴 Edge Function
//
// 배포:
//   supabase functions deploy delete-account --project-ref kyadyqbdugpemzimouxr
//
// 동작:
//   1. 요청 헤더의 사용자 JWT로 본인 확인
//   2. service_role 권한으로 해당 auth 유저 삭제
//   3. profiles 및 cascade 연결 데이터(마을멤버/메시지/게시글/댓글/
//      좋아요/챌린지/인증/친구/DM/차단 등)가 함께 삭제됨

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: '인증 정보가 없습니다.' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // 1. 요청자 JWT로 본인 확인
    const userClient = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return json({ error: '유효하지 않은 사용자입니다.' }, 401);
    }

    // 2. service_role로 계정 삭제 (cascade로 연결 데이터 모두 제거)
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { error: deleteError } =
      await adminClient.auth.admin.deleteUser(user.id);

    if (deleteError) {
      console.error('[DELETE_ACCOUNT] 삭제 실패:', deleteError.message);
      return json({ error: '계정 삭제에 실패했습니다.' }, 500);
    }

    console.log('[DELETE_ACCOUNT] 삭제 완료:', user.id);
    return json({ success: true }, 200);
  } catch (e) {
    console.error('[DELETE_ACCOUNT] 예외:', e);
    return json({ error: '서버 오류가 발생했습니다.' }, 500);
  }
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}