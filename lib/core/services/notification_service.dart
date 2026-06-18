import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/board/models/post.dart';
import '../../features/board/screens/post_detail_screen.dart';
import '../../features/friend/models/friend.dart';
import '../../features/friend/screens/dm_chat_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/village/models/village.dart';
import '../../features/village/screens/village_chat_screen.dart';
import '../../main.dart' show appNavigatorKey, appProviderContainer;

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 알림은 OS가 자동 표시
}

/// FCM 푸시 알림 관리 서비스
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'kyorang_village_default';
  static const String _channelName = '교랑빌리지 알림';
  static const String _channelDesc = '메시지, 친구 요청, 댓글 등';

  // ===========================================================
  // 초기화
  // ===========================================================

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 종료 상태에서 알림으로 시작된 경우 — 라우터 준비될 때까지 대기
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(seconds: 2), () {
        _handleNotificationRoute(initialMessage.data);
      });
    }

    print('[FCM] 초기화 완료');
  }

  // ===========================================================
  // 권한 / 토큰
  // ===========================================================

  Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    print('[FCM] 권한 요청 결과: ${settings.authorizationStatus}');
    return granted;
  }

  Future<void> saveToken() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final token = await _fcm.getToken();
      if (token == null) return;

      await Supabase.instance.client.from('profiles').update({
        'fcm_token': token,
        'fcm_token_updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);

      print('[FCM] 토큰 저장 완료: ${token.substring(0, 20)}...');

      _fcm.onTokenRefresh.listen((newToken) async {
        final currentUid =
            Supabase.instance.client.auth.currentUser?.id;
        if (currentUid == null) return;
        try {
          await Supabase.instance.client.from('profiles').update({
            'fcm_token': newToken,
            'fcm_token_updated_at': DateTime.now().toIso8601String(),
          }).eq('id', currentUid);
          print('[FCM] 토큰 갱신 저장 완료');
        } catch (e) {
          print('[FCM] 토큰 갱신 저장 실패: $e');
        }
      });
    } catch (e) {
      print('[FCM] 토큰 저장 실패: $e');
    }
  }

  Future<void> clearToken() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('profiles').update({
        'fcm_token': null,
      }).eq('id', uid);
      await _fcm.deleteToken();
      print('[FCM] 토큰 정리 완료');
    } catch (e) {
      print('[FCM] 토큰 정리 실패: $e');
    }
  }

  // ===========================================================
  // 메시지 수신
  // ===========================================================

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    print('[FCM] 포그라운드 메시지: ${message.messageId}');
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _local.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    print('[FCM] 알림 클릭(백그라운드): ${message.messageId}');
    _handleNotificationRoute(message.data);
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _handleNotificationRoute(data);
    } catch (e) {
      print('[FCM] 페이로드 파싱 실패: $e');
    }
  }

  // ===========================================================
  // 라우팅
  // ===========================================================

  /// 알림 페이로드로 화면 이동.
  /// payload data에 type 키가 있고, type별로 다른 화면으로 이동한다.
  Future<void> _handleNotificationRoute(Map<String, dynamic> data) async {
    print('[FCM] 라우팅 페이로드: $data');

    final type = data['type'] as String?;
    if (type == null) return;

    // Navigator가 준비될 때까지 잠시 대기
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      print('[FCM] Navigator 미준비 - 라우팅 건너뜀');
      return;
    }

    try {
      switch (type) {
        case 'dm':
          await _routeToDm(data, nav);
          break;
        case 'mention':
        case 'village_chat':
          await _routeToVillageChat(data, nav);
          break;
        case 'post_comment':
        case 'comment_reply':
          await _routeToPost(data, nav);
          break;
        case 'friend_request':
          await _routeToChatsTab(nav);
          break;
        default:
          print('[FCM] 알 수 없는 type: $type');
      }
    } catch (e) {
      print('[FCM] 라우팅 실패: $e');
    }
  }

  /// DM 채팅으로 이동
  Future<void> _routeToDm(
    Map<String, dynamic> data,
    NavigatorState nav,
  ) async {
    final roomId = data['room_id'] as String?;
    if (roomId == null) return;

    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;

    final row = await Supabase.instance.client
        .from('dm_rooms')
        .select(
          '*, user1:profiles!dm_rooms_user1_id_fkey(nickname, avatar_url), '
          'user2:profiles!dm_rooms_user2_id_fkey(nickname, avatar_url)',
        )
        .eq('id', roomId)
        .maybeSingle();

    if (row == null) return;
    final room = DmRoom.fromJson(row, myId);

    nav.push(
      MaterialPageRoute(builder: (_) => DmChatScreen(room: room)),
    );
  }

  /// 마을 채팅으로 이동
  Future<void> _routeToVillageChat(
    Map<String, dynamic> data,
    NavigatorState nav,
  ) async {
    final villageId = data['village_id'] as String?;
    if (villageId == null) return;

    final row = await Supabase.instance.client
        .from('villages')
        .select()
        .eq('id', villageId)
        .maybeSingle();

    if (row == null) return;
    final village = Village.fromJson(row, isJoined: true);

    nav.push(
      MaterialPageRoute(
        builder: (_) => VillageChatScreen(village: village),
      ),
    );
  }

  /// 게시글 상세로 이동
  Future<void> _routeToPost(
    Map<String, dynamic> data,
    NavigatorState nav,
  ) async {
    final postId = data['post_id'] as String?;
    if (postId == null) return;

    final row = await Supabase.instance.client
        .from('posts')
        .select(
          '*, profiles!posts_author_id_fkey(nickname, avatar_url)',
        )
        .eq('id', postId)
        .maybeSingle();

    if (row == null) return;

    // 좋아요 여부 별도 조회 (post_likes 테이블 - 일반적인 이름)
    bool isLiked = false;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId != null) {
      try {
        final likeRow = await Supabase.instance.client
            .from('post_likes')
            .select('post_id')
            .eq('post_id', postId)
            .eq('user_id', myId)
            .maybeSingle();
        isLiked = likeRow != null;
      } catch (e) {
        // 테이블 이름이 다르거나 조회 실패해도 false로 처리
        print('[FCM] isLiked 조회 실패 (기본값 사용): $e');
      }
    }

    final post = Post.fromJson(row, isLiked: isLiked);

    nav.push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
    );
  }

  /// 채팅 탭으로 이동 (친구 요청 알림)
  Future<void> _routeToChatsTab(NavigatorState nav) async {
    // 홈 위에 쌓인 화면들 다 닫고
    nav.popUntil((route) => route.isFirst);
    // 채팅 탭(2)으로 전환 — homeTabIndexProvider 변경
    try {
      appProviderContainer.read(homeTabIndexProvider.notifier).set(2);
    } catch (e) {
      print('[FCM] 탭 변경 실패: $e');
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});