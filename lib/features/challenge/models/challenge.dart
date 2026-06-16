/// 챌린지 모델 (challenges 테이블)
class Challenge {
  const Challenge({
    required this.id,
    required this.villageId,
    required this.creatorId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    this.description,
    this.participantCount = 0,
    this.isParticipating = false,
    this.myCheckinCount = 0,
    this.hasCheckedInToday = false,
  });

  final String id;
  final String villageId;
  final String creatorId;
  final String title;
  final String? description;
  final DateTime startDate; // 날짜만 의미 있음
  final DateTime endDate;
  final DateTime createdAt;

  // ---- 클라이언트 계산 필드 ----
  final int participantCount;
  final bool isParticipating;
  final int myCheckinCount;
  final bool hasCheckedInToday;

  /// 챌린지 전체 일수 (시작일, 종료일 포함)
  int get totalDays => endDate.difference(startDate).inDays + 1;

  /// 오늘 기준 진행 상태
  ChallengeStatus get status {
    final today = _dateOnly(DateTime.now());
    if (today.isBefore(_dateOnly(startDate))) return ChallengeStatus.upcoming;
    if (today.isAfter(_dateOnly(endDate))) return ChallengeStatus.ended;
    return ChallengeStatus.active;
  }

  /// 내 달성률 (0.0 ~ 1.0)
  double get myProgress =>
      totalDays == 0 ? 0 : (myCheckinCount / totalDays).clamp(0.0, 1.0);

  /// 기간 표시용 문자열 (예: 6.15 ~ 6.30)
  String get periodLabel =>
      '${startDate.month}.${startDate.day} ~ ${endDate.month}.${endDate.day}';

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  factory Challenge.fromJson(
    Map<String, dynamic> json, {
    int participantCount = 0,
    bool isParticipating = false,
    int myCheckinCount = 0,
    bool hasCheckedInToday = false,
  }) {
    return Challenge(
      id: json['id'] as String,
      villageId: json['village_id'] as String,
      creatorId: json['creator_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      participantCount: participantCount,
      isParticipating: isParticipating,
      myCheckinCount: myCheckinCount,
      hasCheckedInToday: hasCheckedInToday,
    );
  }

  Challenge copyWith({
    int? participantCount,
    bool? isParticipating,
    int? myCheckinCount,
    bool? hasCheckedInToday,
  }) {
    return Challenge(
      id: id,
      villageId: villageId,
      creatorId: creatorId,
      title: title,
      description: description,
      startDate: startDate,
      endDate: endDate,
      createdAt: createdAt,
      participantCount: participantCount ?? this.participantCount,
      isParticipating: isParticipating ?? this.isParticipating,
      myCheckinCount: myCheckinCount ?? this.myCheckinCount,
      hasCheckedInToday: hasCheckedInToday ?? this.hasCheckedInToday,
    );
  }
}

/// 챌린지 진행 상태
enum ChallengeStatus {
  upcoming('시작 전'),
  active('진행 중'),
  ended('종료');

  const ChallengeStatus(this.label);
  final String label;
}

/// 챌린지 인증 모델 (challenge_checkins + profiles 조인)
class ChallengeCheckin {
  const ChallengeCheckin({
    required this.id,
    required this.challengeId,
    required this.userId,
    required this.userNickname,
    required this.checkinDate,
    required this.createdAt,
    this.userAvatarUrl,
    this.content,
    this.imageUrl,
  });

  final String id;
  final String challengeId;
  final String userId;
  final String userNickname;
  final String? userAvatarUrl;
  final String? content;
  final String? imageUrl;
  final DateTime checkinDate;
  final DateTime createdAt;

  factory ChallengeCheckin.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return ChallengeCheckin(
      id: json['id'] as String,
      challengeId: json['challenge_id'] as String,
      userId: json['user_id'] as String,
      userNickname: profile?['nickname'] as String? ?? '알 수 없음',
      userAvatarUrl: profile?['avatar_url'] as String?,
      content: json['content'] as String?,
      imageUrl: json['image_url'] as String?,
      checkinDate: DateTime.parse(json['checkin_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  String get dateLabel => '${checkinDate.month}.${checkinDate.day}';
}