import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 교랑빌리지 컬러 시스템
/// 컨셉: 따뜻한 오후의 마을 - 크림 배경 + 테라코타 + 숲 초록
/// 하드코딩 컬러 금지. 모든 화면은 이 클래스의 상수만 사용한다.
class AppTheme {
  AppTheme._();

  // ===== 브랜드 컬러 =====
  /// 메인 - 테라코타 (지붕, 흙의 따뜻함)
  static const Color primary = Color(0xFFE07B54);
  static const Color primaryLight = Color(0xFFF2A47E);
  static const Color primaryDark = Color(0xFFC25E3A);

  /// 서브 - 숲 초록 (마을 뒷산)
  static const Color secondary = Color(0xFF7FA86F);
  static const Color secondaryLight = Color(0xFFA8C79B);
  static const Color secondaryDark = Color(0xFF5C8350);

  /// 포인트 - 햇살 노랑
  static const Color accent = Color(0xFFF5C26B);

  /// 교랑 브랜드 퍼플 (생태계 연결용 - 교랑이 캐릭터 주변에서만 사용)
  static const Color kyorangPurple = Color(0xFF7C6BB5);

  // ===== 배경 =====
  static const Color bgMain = Color(0xFFFDF8F1); // 크림
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgSoft = Color(0xFFF7EEE2); // 살짝 진한 크림 (입력창, 칩)

  // ===== 텍스트 =====
  static const Color textMain = Color(0xFF3D3229); // 따뜻한 브라운 블랙
  static const Color textSub = Color(0xFF8A7D6F);
  static const Color textLight = Color(0xFFB5A998);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ===== 기능 컬러 =====
  static const Color divider = Color(0xFFEDE4D7);
  static const Color error = Color(0xFFD95B5B);
  static const Color success = Color(0xFF6FA877);

  // ===== 그라데이션 =====
  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF2A47E), Color(0xFFE07B54)],
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFDF8F1), Color(0xFFF9E8D8)],
  );

  // ===== 둥글기 =====
  static const double radiusS = 10;
  static const double radiusM = 16;
  static const double radiusL = 24;
  static const double radiusFull = 999;

  // ===== 폰트 =====
  /// 본문: Noto Sans KR
  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = textMain,
    double? height,
  }) {
    return GoogleFonts.notoSansKr(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  /// 포인트 손글씨: Gaegu (마을 간판, 인사말 등에만 사용)
  static TextStyle display({
    double size = 22,
    FontWeight weight = FontWeight.w700,
    Color color = textMain,
  }) {
    return GoogleFonts.gaegu(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  // ===== ThemeData =====
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgMain,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: textOnPrimary,
        secondary: secondary,
        onSecondary: textOnPrimary,
        surface: bgCard,
        onSurface: textMain,
        error: error,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.notoSansKrTextTheme(base.textTheme).apply(
        bodyColor: textMain,
        displayColor: textMain,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgMain,
        foregroundColor: textMain,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textMain,
        ),
        iconTheme: const IconThemeData(color: textMain),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textOnPrimary,
          disabledBackgroundColor: divider,
          disabledForegroundColor: textLight,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
          textStyle: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.notoSansKr(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSoft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: GoogleFonts.notoSansKr(fontSize: 14, color: textLight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
          side: const BorderSide(color: divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgCard,
        selectedItemColor: primary,
        unselectedItemColor: textLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textMain,
        contentTextStyle: GoogleFonts.notoSansKr(
          fontSize: 14,
          color: bgCard,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgSoft,
        selectedColor: primary,
        labelStyle: GoogleFonts.notoSansKr(fontSize: 13, color: textSub),
        secondaryLabelStyle: GoogleFonts.notoSansKr(
          fontSize: 13,
          color: textOnPrimary,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
    );
  }
}