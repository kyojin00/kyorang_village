import 'package:flutter/material.dart';

import '../models/village.dart';

/// 마을 카테고리 아이콘 위젯
/// VillageCategory.iconPath 의 PNG 를 렌더하고,
/// 이미지 로딩이 실패하면 자동으로 emoji 텍스트로 폴백한다.
///
/// 사용처: 마을 상세 헤더 / 마을 카드 / 탐색 탭 / 관심사 칩 등
/// size 는 아이콘의 한 변 길이(px). 이모지 폴백 시 폰트 크기는 size * 0.8 로 맞춘다.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.category,
    this.size = 26,
  });

  final VillageCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      category.iconPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // 에셋 누락 / 디코딩 실패 시 이모지로 폴백
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              category.emoji,
              style: TextStyle(fontSize: size * 0.8),
            ),
          ),
        );
      },
    );
  }
}