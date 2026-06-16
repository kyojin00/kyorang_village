// 교랑빌리지 어드민 신고 처리 Edge Function
//
// 배포:
//   supabase functions deploy admin-resolve-report --project-ref kyadyqbdugpemzimouxr
//
// 호출 (kyorang-admin에서):
//   POST /functions/v1/admin-resolve-report
//   Headers: Authorization: Bearer <admin user JWT>, x-admin-key: <ADMIN_API_KEY>
//   Body: { report_id, action, note? }
//
//   action 종류:
//     - "dismiss"        : 무혐의 (신고만 처리됨으로 마킹)
//     - "delete_content" : 신고된 콘텐츠 삭제 (post/comment/message만)
//     - "ban_user"       : 사용자 정지 (target이 user거나, 콘텐츠 작성자)
//     - "unban_user"     : 정지 해제 (target user)
//
// 보안:
//   - 일반 사용자 JWT는 통과 못 함. x-admin-key 시크릿 일치 필수.
//   - ADMIN_API_KEY 시크릿은 Supabase 대시보드 → Edge Functions → Secrets에서 설정.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-admin-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 1. 어드민 키 검증
    const adminKey = req.headers.get('x-admin-key');
    const expectedKey = Deno.env.get('ADMIN_API_KEY');
    if (!expectedKey || adminKey !== expectedKey) {
      return json({ error: '권한이 없습니다.' }, 403);
    }

    // 2. 어드민 사용자 JWT 확인 (감사 로그용 - 누가 처리했는지 기록)
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: '인증 정보가 없습니다.' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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

    // 3. 요청 파싱
    const body = await req.json().catch(() => ({}));
    const reportId = body.report_id as string | undefined;
    const action = body.action as string | undefined;
    const note = body.note as string | undefined;

    if (!reportId || !action) {
      return json({ error: 'report_id와 action이 필요합니다.' }, 400);
    }
    if (!['dismiss', 'delete_content', 'ban_user', 'unban_user'].includes(action)) {
      return json({ error: '알 수 없는 action입니다.' }, 400);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // 4. 신고 조회
    const { data: report, error: reportError } = await admin
      .from('reports')
      .select('*')
      .eq('id', reportId)
      .single();

    if (reportError || !report) {
      return json({ error: '신고를 찾을 수 없습니다.' }, 404);
    }

    // 5. 액션 실행
    switch (action) {
      case 'dismiss':
        await markResolved(admin, reportId, user.id, 'dismissed', note);
        return json({ success: true, action: 'dismissed' });

      case 'delete_content': {
        const ok = await deleteTargetContent(
          admin,
          report.target_type,
          report.target_id,
        );
        if (!ok) {
          return json(
            { error: '이 신고 대상은 콘텐츠 삭제로 처리할 수 없습니다.' },
            400,
          );
        }
        await markResolved(admin, reportId, user.id, 'resolved', note);
        return json({ success: true, action: 'content_deleted' });
      }

      case 'ban_user': {
        const targetUserId = await resolveUserIdFromReport(
          admin,
          report.target_type,
          report.target_id,
        );
        if (!targetUserId) {
          return json(
            { error: '정지할 사용자를 찾을 수 없습니다.' },
            400,
          );
        }
        await admin
          .from('profiles')
          .update({
            is_banned: true,
            banned_at: new Date().toISOString(),
            banned_reason: note ?? report.reason,
          })
          .eq('id', targetUserId);

        await markResolved(admin, reportId, user.id, 'resolved', note);
        return json({
          success: true,
          action: 'user_banned',
          user_id: targetUserId,
        });
      }

      case 'unban_user': {
        const targetUserId = await resolveUserIdFromReport(
          admin,
          report.target_type,
          report.target_id,
        );
        if (!targetUserId) {
          return json(
            { error: '대상 사용자를 찾을 수 없습니다.' },
            400,
          );
        }
        await admin
          .from('profiles')
          .update({
            is_banned: false,
            banned_at: null,
            banned_reason: null,
          })
          .eq('id', targetUserId);

        return json({
          success: true,
          action: 'user_unbanned',
          user_id: targetUserId,
        });
      }
    }

    return json({ error: '처리되지 않은 action' }, 500);
  } catch (e) {
    console.error('[ADMIN_RESOLVE] 예외:', e);
    return json({ error: '서버 오류가 발생했습니다.' }, 500);
  }
});

// ===========================================================
// 헬퍼
// ===========================================================

async function markResolved(
  admin: SupabaseClient,
  reportId: string,
  adminUserId: string,
  status: 'resolved' | 'dismissed',
  note?: string,
) {
  await admin
    .from('reports')
    .update({
      status,
      resolved_at: new Date().toISOString(),
      resolved_by: adminUserId,
      resolution_note: note ?? null,
    })
    .eq('id', reportId);
}

/// 신고 대상 콘텐츠를 삭제. 가능하면 true, 사용자 대상 등 삭제 불가면 false.
async function deleteTargetContent(
  admin: SupabaseClient,
  targetType: string,
  targetId: string,
): Promise<boolean> {
  switch (targetType) {
    case 'post':
      await admin.from('posts').delete().eq('id', targetId);
      return true;
    case 'comment':
      await admin.from('comments').delete().eq('id', targetId);
      return true;
    case 'message':
      await admin.from('village_messages').delete().eq('id', targetId);
      // DM 메시지일 수도 있음 - 둘 다 시도
      await admin.from('dm_messages').delete().eq('id', targetId);
      return true;
    case 'village':
      await admin.from('villages').delete().eq('id', targetId);
      return true;
    case 'user':
      return false; // 사용자는 ban_user로 처리
    default:
      return false;
  }
}

/// 신고 대상에서 작성자/사용자 id를 추출
async function resolveUserIdFromReport(
  admin: SupabaseClient,
  targetType: string,
  targetId: string,
): Promise<string | null> {
  switch (targetType) {
    case 'user':
      return targetId;

    case 'post': {
      const { data } = await admin
        .from('posts')
        .select('author_id')
        .eq('id', targetId)
        .maybeSingle();
      return data?.author_id ?? null;
    }
    case 'comment': {
      const { data } = await admin
        .from('comments')
        .select('author_id')
        .eq('id', targetId)
        .maybeSingle();
      return data?.author_id ?? null;
    }
    case 'message': {
      const vm = await admin
        .from('village_messages')
        .select('sender_id')
        .eq('id', targetId)
        .maybeSingle();
      if (vm.data?.sender_id) return vm.data.sender_id;
      const dm = await admin
        .from('dm_messages')
        .select('sender_id')
        .eq('id', targetId)
        .maybeSingle();
      return dm.data?.sender_id ?? null;
    }
    case 'village': {
      const { data } = await admin
        .from('villages')
        .select('owner_id')
        .eq('id', targetId)
        .maybeSingle();
      return data?.owner_id ?? null;
    }
    default:
      return null;
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}