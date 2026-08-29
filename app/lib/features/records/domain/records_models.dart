import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';

/// 순수 도메인 — 기록(운동/인바디/체형) 탭. Flutter/외부 의존 0, codegen 0.

/// WorkoutLog.exercises 한 항목(API계약 v1.4 Exercise).
/// reps는 문자열("12"·"10-12"·"30초"), [weightKg] 0 = 자중/해당 없음.
class ExerciseEntry {
  const ExerciseEntry({
    required this.name,
    required this.sets,
    required this.reps,
    this.weightKg = 0,
  });

  final String name;
  final int sets;
  final String reps;

  /// 0 = 자중(맨몸)/해당 없음 — UI는 "자중"으로 표기.
  final double weightKg;
}

/// API계약 v1.4 — WorkoutLog(수업 기록). 트레이너가 완료 처리 직후 남기는 30초
/// 기록(P29)을 GET /v1/workout-logs?member=로 조회한다(코어 루프의 마지막 조각).
class WorkoutLog {
  const WorkoutLog({
    required this.id,
    required this.date,
    required this.title,
    required this.exercises,
    this.coachComment,
  });

  final String id;
  final DateTime date;
  final String title;
  final List<ExerciseEntry> exercises;
  final String? coachComment;
}

/// GET /v1/hw-checks 한 건의 집계 입력(도메인 뷰) — 날짜 + done 배열만.
/// HomeworkWeekRules.summarize가 주 단위(월~일)로 묶는다.
class HomeworkCheckDay {
  const HomeworkCheckDay({required this.date, required this.done});

  final DateTime date;
  final List<bool> done;
}

/// Home Work 주간 기록 한 행 — GET /v1/hw-checks?member= 실데이터를
/// HomeworkWeekRules로 주 단위 집계한 결과(v1.4 — mock 대체).
class HomeworkWeekSummary {
  const HomeworkWeekSummary({
    required this.label,
    required this.done,
    required this.total,
    required this.isCurrent,
  });

  final String label;
  final int done;
  final int total;
  final bool isCurrent;
}

class InbodyRecord {
  const InbodyRecord({
    required this.id,
    required this.date,
    required this.weight,
    required this.smm,
    required this.bfm,
    required this.pbf,
    required this.vfl,
    required this.bmr,
    this.source,
  });

  /// 서버가 준 레코드 id. 종전엔 DTO까지 와서 화면 직전에 버려졌고, 그래서
  /// **삭제 대상을 특정할 수 없었다**(오입력이 영구 확정됐다).
  final String id;

  final DateTime date;
  final double weight;
  final double smm;
  final double bfm;
  final double pbf;
  final double vfl;
  final double bmr;

  /// 누가 넣은 기록인가(`member_self` = 회원 본인, 그 외 = 코치·기존 레코드).
  ///
  /// **nullable이어야 한다.** 서버가 이 필드를 채우기 전에 만들어진 레코드는
  /// 값이 없고, required로 두면 그 전부가 파싱에서 던져 기록 탭 세 개를 통째로
  /// 죽인다(같은 사고의 전례가 `records_repository_impl.dart`의 날짜 가드 주석에
  /// 남아 있다). `null`은 "출처 미상"이지 "회원 본인"이 아니다 —
  /// 삭제 액션은 [isMemberSelf]가 참일 때만 붙는다.
  final String? source;

  /// 회원 본인이 앱에서 넣은 기록인가 — 삭제 액션을 붙일 유일한 조건.
  bool get isMemberSelf => source == memberSelfSource;

  /// 서버가 Principal로 판정해 채우는 값. 앱은 **요청에 보내지 않는다**
  /// (`decodeJSON`이 DisallowUnknownFields라 미지 필드는 400).
  static const memberSelfSource = 'member_self';
}

/// 같은 포즈끼리 비교하는 체형 사진 타임라인.
class BodyPhotoTimeline {
  const BodyPhotoTimeline({required this.pose, required this.entries});

  /// 포즈 key 원문.
  final String pose;

  /// 오래된 순.
  final List<BodyPhotoEntry> entries;
}

/// 회원이 가진 체형 사진 **전부**를 포즈별로 나눠 담은 것.
///
/// 포즈는 회원마다 다르다(계약 v2.10) — 대표가 어드민에서 시퀀스를 정하고 커스텀 포즈를
/// 만든다. 그래서 키가 enum이 아니라 **key 문자열**이고, 표시 목록은
/// [poseKeys]가 "현재 시퀀스 ∪ 실제 사진에 있는 key"의 합집합으로 만든다.
///
/// 합집합인 이유: 대표가 포즈를 바꾸거나 지워도 **이미 찍은 사진은 계속 보여야 한다.**
/// 시퀀스만 쓰면 옛 사진이 앱에서 통째로 사라지고(삭제 API도 없다), 사진 키만 쓰면
/// 아직 안 찍은 포즈가 안내에 안 뜬다.
class BodyPhotoAlbum {
  const BodyPhotoAlbum(this.byPose);

  /// 포즈 key → 그 포즈의 사진들(**오래된 순**). 사진이 0장인 포즈는 키가 없을 수 있다.
  final Map<String, List<BodyPhotoEntry>> byPose;

  /// 조회 실패 · 아직 0장일 때의 빈 앨범.
  static const empty = BodyPhotoAlbum(<String, List<BodyPhotoEntry>>{});

  /// 평평한 목록을 포즈별로 묶는다(각 포즈 안에서 오래된 순 정렬).
  factory BodyPhotoAlbum.from(List<BodyPhotoEntry> photos) {
    final grouped = <String, List<BodyPhotoEntry>>{};
    for (final p in photos) {
      (grouped[p.pose] ??= <BodyPhotoEntry>[]).add(p);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }
    return BodyPhotoAlbum(grouped);
  }

  List<BodyPhotoEntry> entriesFor(String pose) => byPose[pose] ?? const <BodyPhotoEntry>[];

  int countFor(String pose) => entriesFor(pose).length;

  int get totalCount => byPose.values.fold(0, (sum, l) => sum + l.length);

  bool get isEmpty => totalCount == 0;

  BodyPhotoTimeline timelineFor(String pose) =>
      BodyPhotoTimeline(pose: pose, entries: entriesFor(pose));

  /// 화면에 띄울 포즈 목록 — **현재 시퀀스 순서 + 시퀀스에 없는 실데이터 key**.
  ///
  /// 뒤쪽에 붙는 잔여 key가 "대표가 뺐지만 사진은 남아 있는 포즈"다. 순서를 시퀀스
  /// 우선으로 두는 이유: 회원이 지금 찍어야 할 포즈가 먼저 보여야 한다.
  List<String> poseKeys(List<PoseSpec> sequence) {
    final keys = <String>[for (final p in sequence) p.key];
    final leftovers = byPose.keys.where((k) => !keys.contains(k)).toList()..sort();
    return [...keys, ...leftovers];
  }

  /// 기록 탭이 처음 열 포즈 — **사진이 가장 많은 포즈**, 동수면 [poseKeys] 순서에서 앞선 쪽.
  ///
  /// 예전 기본값은 `ohsquat` 고정이었다. 촬영 시퀀스의 **마지막** 포즈라 도중에 그만둔
  /// 회원에겐 늘 0장이고, 그래서 첫 진입이 대개 "아직 촬영한 사진이 없어요"였다 —
  /// 방금 찍은 사진을 보러 온 회원에게 가장 나쁜 첫 화면이다.
  ///
  /// "가장 많은 포즈"인 이유: 이 탭의 목적은 전/후 **비교**이고, 비교가 성립하려면 2장
  /// 이상이 필요하다. 장수가 최대인 포즈가 비교가 성립할 확률이 가장 높다.
  String defaultPose(List<PoseSpec> sequence) {
    final keys = poseKeys(sequence);
    if (keys.isEmpty) return PoseSpec.fallbackSequence.first.key;
    var best = keys.first;
    var bestCount = countFor(best);
    for (final k in keys.skip(1)) {
      final count = countFor(k);
      if (count > bestCount) {
        best = k;
        bestCount = count;
      }
    }
    return best;
  }
}

class RecordsData {
  const RecordsData({
    required this.workoutLogs,
    required this.homeworkWeeks,
    required this.inbodyRecords,
    required this.bodyPhotos,
    this.homeworkWeeksFailed = false,
    this.bodyPhotosFailed = false,
  });

  final List<WorkoutLog> workoutLogs;
  final List<HomeworkWeekSummary> homeworkWeeks;
  final List<InbodyRecord> inbodyRecords;

  /// 포즈 4종 전부 — 어느 포즈를 그릴지는 화면의 포즈 칩이 정한다([BodyPhotoAlbum]).
  final BodyPhotoAlbum bodyPhotos;

  /// hw-checks 조회 실패 여부 — best-effort 폴백(빈 목록)을 "기록 없음"으로
  /// 위장하지 않고 UI가 "불러오지 못했어요"로 구분 표시하기 위한 플래그.
  final bool homeworkWeeksFailed;

  /// 체형사진 조회 실패 여부 — 같은 이유의 같은 규약. 실패를 빈 타임라인으로
  /// 두면 "아직 촬영한 사진이 없어요"가 되어, 이미 찍어 둔 회원에게 사진이
  /// 사라진 것처럼 보인다.
  final bool bodyPhotosFailed;
}
