import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'firebase_options.dart';

/// Supabase 설정 (교랑빌리지 전용 프로젝트)
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://kyadyqbdugpemzimouxr.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt5YWR5cWJkdWdwZW16aW1vdXhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNDA5NTksImV4cCI6MjA5NDkxNjk1OX0.sNDZucuVk0_0esIkivrlXC_l35YdIoB0mDWCu2psZ6g';
}

/// 전역 Supabase 클라이언트 접근자
final supabase = Supabase.instance.client;

/// 전역 Navigator key (알림 클릭 시 라우팅용)
/// NotificationService에서 사용
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.bgCard,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.instance.init();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  await Hive.initFlutter();
  await Hive.openBox<String>('settings');

  runApp(
    const ProviderScope(
      child: KyorangVillageApp(),
    ),
  );
}

class KyorangVillageApp extends StatelessWidget {
  const KyorangVillageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '교랑빌리지',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}