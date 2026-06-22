# 교랑빌리지 (Kyorang Village)

관심사 기반 커뮤니티 플랫폼. 비슷한 관심사를 가진 사람들이 **마을**을 만들어 모이고, 그 안에서 채팅·게시판·챌린지로 함께 활동하는 Flutter 앱이다.

> **설계 원칙 — 위계 없는 커뮤니티**
> 마을/커뮤니티 영역에는 결제·수익화 기능을 넣지 않는다. 돈이 들어오면 위계가 생기기 때문이다. 모든 이웃은 동등하다.

---

## 핵심 개념

- **마을 (Village)** — 하나의 관심사를 중심으로 모이는 공간. 채팅·게시판·챌린지로 들어가는 현관 역할을 한다.
- **이웃 (Member)** — 마을에 가입한 사람. 방장(owner)과 일반 멤버(member)로 나뉜다.
- **관심사 (Interests)** — 프로필에 등록하는 분야. 마을 카테고리 체계를 그대로 재활용한다(최대 5개).
- **친구 / DM** — 이웃과 친구를 맺고 1:1 대화를 나눈다.

### 카테고리 (12종)

마을 카테고리와 프로필 관심사는 동일한 `VillageCategory` 체계를 공유한다.

| code | 라벨 | code | 라벨 |
|---|---|---|---|
| `study` | 공부 | `food` | 요리·맛집 |
| `exercise` | 운동 | `travel` | 여행 |
| `reading` | 독서 | `career` | 커리어 |
| `hobby` | 취미 | `mind` | 마음챙김 |
| `music` | 음악 | `etc` | 기타 |
| `game` | 게임 | | |
| `pet` | 반려동물 | | |

각 카테고리는 PNG 아이콘(`assets/icons/villages/<code>.png`)으로 렌더되며, 에셋 로딩 실패 시 이모지로 자동 폴백된다.

---

## 주요 기능

### 마을
- 마을 탐색 (검색 · 카테고리 필터)
- 마을 생성 (이름 · 카테고리 · 소개 · 최대 인원 20/50/100/300)
- 가입 / 탈퇴, 방장의 마을 삭제
- 마을 채팅 (실시간)
- 게시판 (글 · 사진 · 반응 이모지)
- 챌린지 (목표 설정 및 인증)
- 이웃 목록 보기

### 친구 / 메신저
- 친구 신청 · 수락 · 거절 · 취소 · 끊기
- 1:1 DM
- 공용 프로필 바텀시트

### 프로필
- 닉네임 · 상태 메시지 · 자기소개 인라인 편집
- 프로필 사진 · 커버 사진 (갤러리 업로드, 풀스크린 뷰어)
- 관심사 선택 (최대 5개)

### 안전
- 차단 / 차단 해제 (차단 시 채팅·게시글·댓글 숨김)
- 신고 (사유 선택)

### 기타
- 온보딩 화면 (최초 1회)
- 안 읽음 카운트 뱃지

---

## 기술 스택

| 영역 | 사용 기술 |
|---|---|
| 프레임워크 | Flutter |
| 상태관리 | Riverpod |
| 백엔드 | Supabase (DB · Auth · Realtime · Storage) |
| 인증/푸시 | Firebase (Auth · FCM) |
| 이미지 | cached_network_image |

> 정확한 패키지·버전은 `pubspec.yaml`을 기준으로 한다.

### 테마

다크 퍼플 톤을 사용한다.

- 배경: `#060610` / `#080810`
- 강조색(accent): `#7c3aed`
- 모든 색상·간격·라운드는 `AppTheme`를 통해 사용하며, 하드코딩하지 않는다.

---

## 프로젝트 구조

기능(feature) 단위로 폴더를 나누고, 공통 코드는 `core`에 둔다.

```
lib/
├── core/
│   ├── services/          # auth, storage, safety, unread 등 공통 서비스
│   ├── theme/
│   │   └── app_theme.dart # 색상·타이포·라운드 정의 (단일 소스)
│   └── widgets/
│       └── fullscreen_image_viewer.dart
│
└── features/
    ├── home/
    │   └── home_shell.dart        # 하단 탭바 (내 마을 · 탐색 · 프로필 등)
    │
    ├── village/                   # 마을 도메인
    │   ├── models/
    │   │   └── village.dart       # VillageCategory · Village · VillageMember
    │   ├── services/
    │   │   └── village_service.dart
    │   ├── widgets/
    │   │   └── category_icon.dart # 카테고리 PNG 렌더 + 이모지 폴백 위젯
    │   └── screens/
    │       ├── explore_tab.dart
    │       ├── my_villages_tab.dart
    │       ├── create_village_screen.dart
    │       ├── village_detail_screen.dart
    │       ├── village_chat_screen.dart
    │       └── village_members_sheet.dart
    │
    ├── board/                     # 게시판
    │   ├── models/post.dart
    │   └── screens/
    │       ├── board_screen.dart
    │       └── post_detail_screen.dart
    │
    ├── challenge/
    │   └── screens/challenge_list_screen.dart
    │
    ├── friend/                    # 친구 · DM
    │   ├── models/friend.dart
    │   ├── services/
    │   │   ├── friend_service.dart
    │   │   └── dm_service.dart
    │   ├── widgets/profile_sheet.dart
    │   └── screens/dm_chat_screen.dart
    │
    ├── profile/
    │   └── screens/
    │       ├── my_profile_screen.dart
    │       └── interests_edit_sheet.dart
    │
    └── onboarding/
        └── onboarding_screen.dart
```

---

## 데이터 모델 (Supabase)

주요 테이블 개요.

- **profiles** — `nickname`, `bio`, `status_message`, `avatar_url`, `cover_url`, `interests`(text[])
- **villages** — `name`, `category`, `description`, `cover_url`, `owner_id`, `member_count`, `max_members`, `is_private`, `created_at`
- **village_members** — `village_id`, `user_id`, `role`(owner|member), `joined_at`
- **friendships** — 친구 관계 (신청/수락 상태 포함)
- **DM 관련** — 1:1 대화방 및 메시지
- **차단 / 신고** — 안전 기능용

### RLS 관련 메모

- 필터 없는 `postgres_changes`는 RLS 환경에서 동작하지 않으므로, 실시간 목록·알림은 **broadcast 채널**을 사용한다.
- RLS 순환 참조는 `SECURITY DEFINER` 헬퍼 함수로 끊는다 (예: `is_room_member()`).
- Supabase 무료 티어 프로젝트는 자동 일시정지되므로, 갑작스러운 502/CORS 발생 시 프로젝트 상태를 먼저 확인한다.

---

## 카테고리 아이콘 시스템

카테고리 이모지를 직접 그리지 않고, 전 화면에서 `CategoryIcon` 위젯으로 통일했다.

```dart
CategoryIcon(category: cat, size: 38)
```

- `VillageCategory.iconPath`의 PNG를 `Image.asset`으로 렌더한다.
- 에셋 누락·디코딩 실패 시 `errorBuilder`로 `VillageCategory.emoji`를 폴백 표시한다.
- 따라서 PNG가 빠져도 화면이 깨지지 않는다.

**아이콘 변경 시:** `assets/icons/villages/<code>.png` 파일만 교체하면 되고 코드는 건드릴 필요가 없다.

> `VillageCategory.emoji` 필드는 폴백 용도로 계속 필요하므로 제거하지 않는다.

### 화면별 아이콘 크기

| 위치 | size |
|---|---|
| 마을 상세 헤더 | 40 |
| 내 마을 카드 / 탐색 카드 | 38 |
| 각종 칩 (탐색·생성·관심사) | 22 |

---

## 시작하기

### 사전 준비
- Flutter SDK
- Supabase 프로젝트 (URL · anon key)
- Firebase 프로젝트 설정 파일 (`google-services.json` 등)

### 실행

```bash
flutter pub get
flutter run
```

> Flutter 웹에서 Firebase를 쓸 경우 `DefaultFirebaseOptions.currentPlatform`을 `Firebase.initializeApp()`에 명시적으로 전달해야 한다. Android/iOS는 네이티브 설정 파일을 자동으로 읽지만 웹은 그렇지 않다.

### 테스트 환경
- 주 테스트 기기: Galaxy SM-A136S (Android 14, 저사양 MediaTek)

---

## 개발 노트

- **BackdropFilter 주의** — 삼성/MediaTek 기기에서 여러 개의 `BackdropFilter(ImageFilter.blur(...))`가 동시에 있으면 GPU 렌더가 멈춘다. 반투명 `Material`로 대체한다.
- **로그 규율** — 대상 앱 PID의 Flutter 태그 로그만 필터링하고 시스템 노이즈는 무시한다.
- **진단 우선** — `[A]`–`[G]` 스타일 print 로깅과 최소 빌드로 원인을 먼저 좁힌 뒤 수정한다.

---

## 라이선스

비공개 프로젝트. (교랑 패밀리)