/// 마을 카테고리 정의
/// DB의 villages.category 컬럼과 1:1 매칭되는 코드 값을 가진다.
class VillageCategory {
  const VillageCategory({
    required this.code,
    required this.label,
    required this.emoji,
  });

  final String code;
  final String label;
  final String emoji;

  /// 전체 카테고리 목록 (탐색 칩, 마을 생성 선택지에 공통 사용)
  static const List<VillageCategory> all = [
    VillageCategory(code: 'study', label: '공부', emoji: '📚'),
    VillageCategory(code: 'exercise', label: '운동', emoji: '💪'),
    VillageCategory(code: 'reading', label: '독서', emoji: '📖'),
    VillageCategory(code: 'hobby', label: '취미', emoji: '🎨'),
    VillageCategory(code: 'music', label: '음악', emoji: '🎵'),
    VillageCategory(code: 'game', label: '게임', emoji: '🎮'),
    VillageCategory(code: 'pet', label: '반려동물', emoji: '🐾'),
    VillageCategory(code: 'food', label: '요리·맛집', emoji: '🍳'),
    VillageCategory(code: 'travel', label: '여행', emoji: '✈️'),
    VillageCategory(code: 'career', label: '커리어', emoji: '💼'),
    VillageCategory(code: 'mind', label: '마음챙김', emoji: '🌿'),
    VillageCategory(code: 'etc', label: '기타', emoji: '🏡'),
  ];

  static VillageCategory fromCode(String code) {
    return all.firstWhere(
      (c) => c.code == code,
      orElse: () => all.last, // 알 수 없는 코드는 '기타' 처리
    );
  }
}

/// 마을 모델 (villages 테이블)
class Village {
  const Village({
    required this.id,
    required this.name,
    required this.category,
    required this.ownerId,
    required this.memberCount,
    required this.maxMembers,
    required this.isPrivate,
    required this.createdAt,
    this.description,
    this.coverUrl,
    this.isJoined = false,
  });

  final String id;
  final String name;
  final String? description;
  final String category;
  final String? coverUrl;
  final String ownerId;
  final int memberCount;
  final int maxMembers;
  final bool isPrivate;
  final DateTime createdAt;

  /// 현재 유저의 가입 여부 (조회 시점에 계산되는 클라이언트 필드)
  final bool isJoined;

  VillageCategory get categoryInfo => VillageCategory.fromCode(category);

  bool get isFull => memberCount >= maxMembers;

  factory Village.fromJson(Map<String, dynamic> json, {bool isJoined = false}) {
    return Village(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      category: json['category'] as String,
      coverUrl: json['cover_url'] as String?,
      ownerId: json['owner_id'] as String,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      maxMembers: (json['max_members'] as num?)?.toInt() ?? 100,
      isPrivate: json['is_private'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      isJoined: isJoined,
    );
  }

  Village copyWith({
    int? memberCount,
    bool? isJoined,
  }) {
    return Village(
      id: id,
      name: name,
      description: description,
      category: category,
      coverUrl: coverUrl,
      ownerId: ownerId,
      memberCount: memberCount ?? this.memberCount,
      maxMembers: maxMembers,
      isPrivate: isPrivate,
      createdAt: createdAt,
      isJoined: isJoined ?? this.isJoined,
    );
  }
}

/// 마을 멤버 모델 (village_members + profiles 조인 결과)
class VillageMember {
  const VillageMember({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.joinedAt,
    this.avatarUrl,
  });

  final String userId;
  final String nickname;
  final String? avatarUrl;
  final String role; // owner | member
  final DateTime joinedAt;

  bool get isOwner => role == 'owner';

  factory VillageMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return VillageMember(
      userId: json['user_id'] as String,
      nickname: profile?['nickname'] as String? ?? '알 수 없음',
      avatarUrl: profile?['avatar_url'] as String?,
      role: json['role'] as String? ?? 'member',
      joinedAt: DateTime.parse(json['joined_at'] as String).toLocal(),
    );
  }
}