// 순수 도메인 — 체형 분석 카메라. Flutter/외부 의존 0, codegen 0.

/// 체형 촬영 시퀀스의 한 단계(계약 v2.10).
///
/// **enum이 아니라 값 타입인 이유**: 포즈는 이제 회원마다 다르다. 대표가 어드민에서
/// 순서·구성을 바꾸고 커스텀 포즈를 만들 수 있으므로(`Member.body_poses`), 컴파일 시점에
/// 목록을 고정하는 enum으로는 담을 수 없다.
///
/// key는 Storage 파일명 `{yyyyMMdd}-{pose}-{direction}-{epochMs}.jpg`의 조각으로 쓰이므로
/// 서버가 슬러그 규칙(`^[a-z0-9_]{1,24}$` — 하이픈 금지)을 강제한다. 앱은 그 전제를 믿되
/// 경로 생성에서 한 번 더 방어한다([BodyPhotoStoragePath]).
class PoseSpec {
  const PoseSpec(this.key, this.label);

  final String key;
  final String label;

  /// 레거시 4종 라벨 — 서버가 목록을 안 줄 때(구버전 서버·오프라인)와, **이미 찍힌 사진의
  /// 포즈가 현재 시퀀스에서 빠졌을 때** 라벨을 복원하는 데 쓴다.
  static const legacyLabels = <String, String>{
    'stand': '차렷',
    'tpose': 'T자',
    'fold': '전굴',
    'ohsquat': 'OH스쿼트',
  };

  /// 서버가 시퀀스를 못 줄 때의 폴백. 서버 `DefaultBodyPoses`와 같은 순서·같은 라벨이다.
  static const fallbackSequence = <PoseSpec>[
    PoseSpec('stand', '차렷'),
    PoseSpec('tpose', 'T자'),
    PoseSpec('fold', '전굴'),
    PoseSpec('ohsquat', 'OH스쿼트'),
  ];

  /// key로 라벨을 푼다: 회원 시퀀스 → 레거시 맵 → **raw key 그대로**.
  ///
  /// 마지막 폴백이 핵심이다 — 종전 `fromWire`는 모르는 key를 `stand`로 떨어뜨렸는데,
  /// 그러면 대표가 포즈를 바꾼 뒤 옛 사진들이 **차렷 앨범에 뒤섞인다**. 모르면 모르는 대로
  /// 보여주는 편이 정직하고, 사진이 사라지지도 않는다.
  static String labelFor(String key, {List<PoseSpec> sequence = const []}) {
    for (final p in sequence) {
      if (p.key == key) return p.label;
    }
    return legacyLabels[key] ?? key;
  }

  @override
  bool operator ==(Object other) =>
      other is PoseSpec && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);

  @override
  String toString() => 'PoseSpec($key, $label)';
}

/// API계약_v1.md BodyPhoto.direction: front|side|back.
enum BodyDirection {
  front('front', '정면'),
  side('side', '측면'),
  back('back', '후면');

  const BodyDirection(this.wireValue, this.label);
  final String wireValue;
  final String label;
}

class BodyPhotoEntry {
  const BodyPhotoEntry({
    required this.id,
    required this.memberId,
    required this.pose,
    required this.direction,
    required this.date,
    this.storagePath,
    required this.blurred,
  });

  final String id;
  final String memberId;

  /// 서버가 준 pose **key 원문**. 현재 시퀀스에 없는 값일 수 있다(대표가 포즈를 바꾼 뒤의
  /// 옛 사진) — 그래도 목록에서 사라지면 안 되므로 enum으로 좁히지 않는다.
  final String pose;
  final BodyDirection direction;
  final DateTime date;
  final String? storagePath;
  final bool blurred;
}
