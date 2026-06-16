import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'safety_service.dart';
import '../theme/app_theme.dart';

/// 정지 계정 처리 유틸
///
/// 로그인 직후 / 스플래시에서 호출.
/// 정지된 계정이면 안내 다이얼로그를 띄우고 로그아웃 → true 반환.
/// 정상 계정이면 false 반환.
class BanCheck {
  BanCheck._();

  /// 현재 세션의 정지 여부를 확인. 정지면 안내 후 강제 로그아웃.
  /// 반환값 true = 정지됨 (다음 화면 전환 중단), false = 정상
  static Future<bool> checkAndHandle(BuildContext context) async {
    final uid = AuthService.instance.currentUserId;
    if (uid == null) return false;

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('is_banned, banned_reason')
          .eq('id', uid)
          .maybeSingle();

      final banned = (row?['is_banned'] as bool?) ?? false;
      if (!banned) return false;

      final reason = row?['banned_reason'] as String?;
      if (!context.mounted) return true;

      await _showBannedDialog(context, reason);

      // 강제 로그아웃
      await AuthService.instance.signOut();
      SafetyService.instance.clearCache();
      return true;
    } catch (e) {
      print('[BAN_CHECK] 확인 실패 (정상으로 처리): $e');
      return false;
    }
  }

  static Future<void> _showBannedDialog(
    BuildContext context,
    String? reason,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text(
          '이용이 제한된 계정이에요',
          style: AppTheme.body(size: 17, weight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '커뮤니티 안전을 위해 이 계정의 이용이 제한되었어요.',
              style: AppTheme.body(
                size: 14,
                color: AppTheme.textSub,
                height: 1.5,
              ),
            ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusS),
                ),
                child: Text(
                  '사유: $reason',
                  style: AppTheme.body(size: 13, color: AppTheme.textMain),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '문의: support@kyorang.com',
              style: AppTheme.body(size: 12, color: AppTheme.textLight),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '확인',
              style: AppTheme.body(
                size: 14,
                color: AppTheme.primary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}