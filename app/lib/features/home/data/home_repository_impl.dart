import 'package:rise_member/core/api/dto/homework_dto.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/home/data/home_remote_data_source.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/domain/homework_schedule_rules.dart';
import 'package:rise_member/features/my/domain/my_models.dart' show PassHold;

class HomeRepositoryImpl implements HomeRepository {
  const HomeRepositoryImpl(
    this._passesApi,
    this._bookingsApi,
    this._remote,
    this._readStaffMap,
  );

  final PassesApi _passesApi;
  final BookingsApi _bookingsApi;
  final HomeRemoteDataSource _remote;

  /// 스태프 맵은 [staffMapReaderProvider]를 통해서만 읽는다 — 앱 전체가 캐시
  /// 하나(staffMapProvider)를 공유하고, 실패해도 빈 맵으로 떨어진다(best-effort).
  final StaffMapReader _readStaffMap;

  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) {
    return guardApi(() async {
      // ── 다섯 요청을 **동시에** 띄운다 ────────────────────────────────────
      //
      // 종전엔 `await`가 다섯 번 줄줄이 있어 왕복이 직렬이었다. 그런데 이들은
      // **서로의 응답을 필요로 하지 않는다** — 의존은 전부 응답을 *가공할 때*
      // 생긴다(예: 홈워크 필터가 `selected.trainerId`를 쓴다). 그래서 요청은
      // 함께 보내고, 기다리는 순서만 종전 그대로 둔다.
      //
      // `_settle`로 감싸는 이유: 아래 `EmptyPassesFailure`처럼 **중간에 빠져나가는
      // 경로**가 있는데, 그때 남은 future가 나중에 실패하면 아무도 받지 않는
      // 비동기 예외가 되어 앱이 죽는다. 감싸 두면 에러가 값으로 잡히고, 원래
      // 코드가 던지던 자리에서 원래 순서대로 다시 던진다.
      final todayKst = DateFmt.todayKst();
      final todayIso = DateFmt.isoDate(todayKst);

      final staffMapF = _settle(_readStaffMap());
      final passesF = _settle(_passesApi.fetchMyPasses(memberId));
      final bookingsF = _settle(_bookingsApi.fetchMyBookings(memberId));
      final homeworksF = _settle(_remote.fetchHomeworks(memberId));
      final checksF =
          _settle(_remote.fetchHwChecks(memberId: memberId, date: todayIso));

      // 이름·퇴사 여부 해석은 부가 정보 — 실패해도 빈 맵으로 돌아와 홈을 죽이지
      // 않는다(staffMapReaderProvider 주석: 왜 "모르면 현직"인지 포함).
      final staffMap = (await staffMapF).valueOr(const {});
      final passDtos = (await passesF).valueOrThrow();
      if (passDtos.isEmpty) {
        // 에러가 아니라 빈 상태 — 홈이 타입으로 구분해 전용 빈 상태 뷰를 렌더한다.
        throw const EmptyPassesFailure();
      }

      final passes = passDtos
          .map((p) => PassOption(
                id: p.id,
                product: p.product,
                trainerId: p.trainerId,
                trainerName: staffMap[p.trainerId]?.name,
                // 계약 v2.0 — inactive 스태프도 /v1/staff에 남으므로 이름은 계속
                // 해석된다. 현직/퇴사 구분만 실어 보내고 표기는 화면이 정한다.
                trainerInactive: staffMap[p.trainerId]?.isInactive ?? false,
                // 휴무일도 같은 응답에서 온다 — 계약상 member에게도 내려주는 필드다
                // (ListStaff는 payout만 비운다). 예약 탭이 휴무일 슬롯을 사전 차단하는
                // 데 쓴다(서버 400 "담당 코치의 휴무일이에요").
                trainerOffdays: staffMap[p.trainerId]?.offdays.toSet() ?? const {},
                status: p.status,
                remaining: p.remaining,
                totalSessions: p.totalSessions,
                validFrom: DateTime.parse(p.validFrom),
                validUntil: DateTime.parse(p.validUntil),
                holds: [
                  for (final h in p.holds)
                    PassHold(from: DateTime.parse(h.from), to: DateTime.parse(h.to), reason: h.reason),
                ],
              ))
          .toList();

      // 기본 선택은 **이용 가능한** 패스만 노린다(active → scheduled). 하나도 없으면
      // null — 그 사실을 [HomeSummary.hasUsablePass]로 위에 올린다.
      final usableDefault = _defaultUsablePass(passes);
      // 폴백이 여전히 `passes.first`인 이유: 이용 가능한 패스가 없어도 `selectedPassId`는
      // 실재하는 id여야 한다. 예약 탭이 이 값을 `primaryPassId`로 받아 대표 패스를
      // 찾고(booking_view_model), 거기서 만료·환불 패스를 `PassNotUsable`로 **직접
      // 안내**한다 — 여기서 id를 비우거나 throw하면 그 안내가 통째로 사라진다.
      // 홈은 대신 hasUsablePass=false를 보고 정상 본문을 그리지 않는다.
      final selected = preferredPassId == null
          ? (usableDefault ?? passes.first)
          : passes.firstWhere(
              (p) => p.id == preferredPassId,
              orElse: () => usableDefault ?? passes.first,
            );

      final bookingDtos = (await bookingsF).valueOrThrow();
      // "지금"은 반드시 센터(KST) 축 — 지난 예약 필터가 slotKey에서 온 벽시계
      // 표현(DateFmt.slotKeyToDateTime)과 뺄셈을 한다. `DateTime.now()`는 기기
      // 로컬이라 해외 체류·기기 시계 오설정 시 오프셋 차만큼 통째로 어긋난다
      // (DateFmt 클래스 주석의 시간축 규약).
      //
      // 여기서 시계를 읽는 판정은 **이 필터 하나뿐이다**(P51). 체크인 시간창과
      // 무료 취소 컷오프는 예전엔 여기서 bool로 계산해 모델에 담았는데, 그 값이
      // 로드 시점에 굳어 시간이 흘러도 안 바뀌었다 — 창이 열려도 버튼이 회색으로
      // 남았다. 지금은 [NextBooking]이 startAt만 들고 가고 화면이 `now`를 넣어
      // 파생 계산한다([NextBooking] 클래스 주석).
      //
      // 이 필터를 굳혀 두는 건 괜찮다: 판정 대상은 "목록에서 어느 예약을 고를까"
      // 이고, 다음 예약이 지나가면 그 자리를 채울 **새 예약 정보 자체가 서버에서
      // 와야** 하므로 어차피 재조회 없이는 갱신할 수 없다. 시각만 다시 재서 카드를
      // 비울 수도 있지만, 수업 시작 1시간 뒤까지는 남겨 두는 게 의도된 동작이다
      // (체크인 창 +30분보다 넉넉히).
      final now = DateFmt.nowKst();
      final upcoming = bookingDtos
          .where((b) => b.status == 'confirmed' && b.trainerId == selected.trainerId)
          .map((b) => (b, DateFmt.slotKeyToDateTime(b.slotKey)))
          .where((pair) => pair.$2.isAfter(now.subtract(const Duration(hours: 1))))
          .toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));

      NextBooking? next;
      if (upcoming.isNotEmpty) {
        final (b, startAt) = upcoming.first;
        next = NextBooking(
          id: b.id,
          startAt: startAt,
          kind: b.kind,
          trainerName: staffMap[b.trainerId]?.name,
          trainerInactive: staffMap[b.trainerId]?.isInactive ?? false,
        );
      }

      // Home Work "오늘"은 센터(KST) 날짜 하나로 통일한다 — 배정 필터(isActiveOn),
      // 체크 조회(GET ?date=), 클라이언트 방어 비교, 그리고 **쓰기**
      // (HomeViewModel.toggleHomework → POST /v1/hw-checks)가 전부 같은 값을 봐야
      // 한다. 읽기만 KST로 올리고 쓰기를 로컬로 두면 해외에서 회원이 체크한 게
      // 다른 날짜 문서에 저장되어 화면에서 되돌아가 보인다.
      // 서버도 date 생략 시 KST 오늘로 채우므로(api/service.go), 이 값이 곧 서버 값이다.
      //
      // **이 값은 요약에 그대로 실려 올라간다**([HomeSummary.homeworkDate]). 축을
      // 맞추는 것만으로는 부족했다 — 쓰기가 시계를 *다시* 읽는 한, 23:50 로드 →
      // 00:05 체크에서 어제 목록이 오늘 문서를 덮는다(P17). 쓰기가 여기서 굳은
      // 날짜를 그대로 받게 해서, 두 시점이 갈릴 여지 자체를 없앤다.
      final homeworks = (await homeworksF).valueOrThrow();
      // 담당 코치 일치 + schedule(once|weekly) 기준으로 "오늘" 항목만.
      // 단, 센터 공지(scope=center_notice)는 담당 코치와 무관하게 항상 노출.
      final todays = homeworks.where((h) {
        if (h.scope != 'center_notice' && h.trainerId != selected.trainerId) return false;
        final s = h.schedule;
        return HomeworkScheduleRules.isActiveOn(
          date: todayKst,
          type: s?.type,
          days: s?.days ?? const [],
          from: s?.from,
          to: s?.to,
        );
      }).toList();

      var checks = <HwCheckDto>[];
      var checksFailed = false;
      final checksR = await checksF;
      if (checksR.error == null) {
        checks = checksR.value!;
      } else {
        // best-effort — 체크 상태 조회 실패해도 배정 목록 자체는 보여준다.
        // 단 아래 done 폴백(false)을 "아직 안 함"으로 위장하면 안 된다: 토글이
        // done 배열 전체를 덮어쓰는 POST라(HomeSummary.homeworkChecksFailed 주석)
        // 서버에 남아 있는 완료 기록이 조용히 지워진다. 플래그로 UI에 전달해
        // 토글을 잠그고, 상태를 모른다는 사실을 화면에 그대로 말한다.
        checksFailed = true;
      }

      final items = <HomeworkItem>[];
      for (final hw in todays) {
        HwCheckDto? check;
        for (final c in checks) {
          // 서버가 date= 필터를 지원하지만 오늘 날짜 일치를 클라이언트에서도 방어.
          if (c.hwId == hw.id && c.date == todayIso) {
            check = c;
            break;
          }
        }
        for (var i = 0; i < hw.items.length; i++) {
          final done = check != null && i < check.done.length ? check.done[i] : false;
          items.add(HomeworkItem(
            hwId: hw.id,
            index: i,
            name: hw.items[i].name,
            // 처방(세트·횟수)은 배정의 **알맹이**다 — 여기서 흘리면 서버·DTO가 제대로
            // 실어 왔어도 회원 앱에는 운동 이름만 남는다("플랭크"를 몇 세트 몇 초?).
            // 값 그대로 옮긴다: reps는 "10-12"·"40초" 같은 문자열 표기라 파싱하지 않고
            // (계약 v1.3), sets의 0/null 구분은 도메인(HomeworkItem.prescription)이 맡는다.
            sets: hw.items[i].sets,
            reps: hw.items[i].reps,
            // 서버는 메모 없음을 `""`로 준다(Go `HwItem.Note`는 string, 포인터가
            // 아니다). 그대로 넘기면 화면이 `'스쿼트 — '`처럼 **구분자만 남긴다** —
            // 실기기 플로우 점검에서 실제로 그렇게 떴다. 빈 문자열은 없는 것으로
            // 정규화한다(CoachLabel.joinDot이 같은 이유로 존재한다).
            note: (hw.items[i].note?.trim().isEmpty ?? true) ? null : hw.items[i].note!.trim(),
            done: done,
          ));
        }
      }

      return HomeSummary(
        passes: passes,
        selectedPassId: selected.id,
        // 선택된 패스가 아니라 **목록 전체**를 본다 — 회원이 만료 칩을 직접 눌러
        // 둔 상태(preferredPassId)까지 "이용 가능한 회원권 없음"으로 떨어뜨리면
        // 스스로 누른 칩이 화면을 지우는 셈이 된다.
        hasUsablePass: usableDefault != null,
        nextBooking: next,
        homeworkItems: items,
        // 위 배정 필터·GET ?date=가 실제로 쓴 날짜 그대로 — 쓰기가 이 값을 받는다.
        homeworkDate: todayKst,
        homeworkChecksFailed: checksFailed,
      );
    });
  }

  /// 홈이 기본으로 골라야 할 패스 — **이용 가능한 것만**. 없으면 null.
  ///
  /// 예전엔 active가 없으면 `passes.first`를 그냥 골랐다. 환불된 패스 하나만 남은
  /// 회원의 홈이 그 패스를 골라 잔여 링·담당 코치·다음 예약을 **정상처럼** 그렸고,
  /// 회원은 이미 환불받은 회원권이 아직 살아 있다고 읽었다.
  ///
  /// 순서는 서버가 쓸 수 있다고 보는 순서 그대로다:
  /// - `active` — `CreateBooking`·`HoldPass`가 유일하게 통과시키는 상태.
  /// - `scheduled` — 아직 시작 전이지만 곧 쓸 패스. 백엔드가 아직 만들지 않지만
  ///   (CreatePass는 항상 active) 계약에 있는 값이라, 만들어지는 날 "회원권 없음"으로
  ///   떨어지지 않도록 여기서 먼저 받는다.
  /// - `expired`·`refunded` 등 종료 상태는 기본 선택하지 않는다. 칩을 직접 탭한
  ///   경우(preferredPassId)는 회원의 명시적 선택이라 그대로 존중한다.
  PassOption? _defaultUsablePass(List<PassOption> passes) {
    for (final p in passes) {
      if (p.isActive) return p;
    }
    for (final p in passes) {
      if (p.isScheduled) return p;
    }
    return null;
  }

  @override
  Future<Result<void>> submitHomeworkChecks({
    required String memberId,
    required String hwId,
    required DateTime date,
    required List<bool> done,
  }) {
    return guardApi(() => _remote.submitHwCheck(
          hwId: hwId,
          date: DateFmt.isoDate(date),
          done: done,
        ));
  }

  @override
  Future<Result<void>> selfCheckIn({String? scannedToken}) {
    return guardApi(() => _remote.selfCheckIn(scannedToken: scannedToken));
  }
}


/// 성공/실패를 **값으로** 담는다 — 던지지 않는다.
///
/// 홈 로드는 다섯 요청을 동시에 띄우는데, 중간에 빠져나가는 경로가 있다
/// (`EmptyPassesFailure`). 그때 남은 future가 나중에 실패하면 **아무도 받지 않는
/// 비동기 예외**가 되어 앱이 죽는다. 감싸 두면 에러가 값으로 잡히고, 원래 코드가
/// 던지던 자리에서 원래 순서대로 다시 던질 수 있다.
class _Settled<T> {
  const _Settled(this.value, this.error, this.stack);
  final T? value;
  final Object? error;
  final StackTrace? stack;

  /// 실패면 그대로 다시 던진다 — **스택을 보존**해서 원인 추적이 끊기지 않게.
  T valueOrThrow() {
    if (error != null) Error.throwWithStackTrace(error!, stack ?? StackTrace.current);
    return value as T;
  }

  /// best-effort 호출용 — 실패하면 대체값.
  T valueOr(T fallback) => error != null ? fallback : value as T;
}

Future<_Settled<T>> _settle<T>(Future<T> f) async {
  try {
    return _Settled(await f, null, null);
  } catch (e, st) {
    return _Settled(null, e, st);
  }
}
