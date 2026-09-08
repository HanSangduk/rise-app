import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/home/data/home_remote_data_source.dart';
import 'package:rise_member/features/home/data/home_repository_impl.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

part 'home_view_model.g.dart';

@riverpod
HomeRepository homeRepository(Ref ref) {
  final dio = ref.watch(dioProvider);
  return HomeRepositoryImpl(
    ref.watch(passesApiProvider),
    ref.watch(bookingsApiProvider),
    HomeRemoteDataSource(dio),
    // StaffDirectory 직접 주입 금지 — 캐시(staffMapProvider)를 우회하게 된다.
    ref.watch(staffMapReaderProvider),
  );
}

@riverpod
class HomeViewModel extends _$HomeViewModel {
  @override
  Future<HomeSummary> build() async {
    final memberId = ref.watch(sessionProvider)?.memberId;
    if (memberId == null) {
      // 셸이 떠 있는 채 세션이 비었다 — 리스너가 이동 중이라 문구가 아닌 타입만 낸다(P64).
      throw const SessionGoneFailure();
    }
    // 정책값 자체는 여기서 쓰지 않는다(취소 컷오프 판정이 화면의 파생 계산으로
    // 옮겨갔다 — [NextBooking] 주석). 그래도 **기다리는 건 남긴다**: 홈 카드가
    // `centerPolicyProvider`를 직접 읽는데, 정책보다 홈 데이터가 먼저 도착하면
    // 컷오프 문구가 폴백 24시간으로 한 프레임 떴다가 실값으로 바뀐다.
    // 정책 provider는 실패해도 폴백을 돌려주므로 여기서 홈 로드를 막지 않는다.
    await ref.watch(centerPolicyProvider.future);
    final repo = ref.watch(homeRepositoryProvider);
    return _unwrap(await repo.loadHome(memberId: memberId));
  }

  T _unwrap<T>(Result<T> r) => switch (r) {
        Ok<T>(:final value) => value,
        Err<T>(:final failure) => throw failure,
      };

  void refresh() => ref.invalidateSelf();

  /// 자정 롤오버 재조회를 이미 요청한 날짜 — 실패해도 같은 날짜로 무한 재시도하지
  /// 않기 위한 메모. `AsyncNotifier`의 인스턴스는 `invalidateSelf` 너머로 살아남고
  /// (build만 다시 돈다) provider가 통째로 폐기되면 함께 사라진다 — 재시도 창을
  /// "하루에 한 번, 이 화면이 사는 동안"으로 묶는 데 딱 맞는 수명이다.
  DateTime? _rolloverRequestedFor;

  /// 로드 시점 날짜([HomeSummary.homeworkDate])가 오늘과 달라졌으면 홈을 다시 읽는다.
  ///
  /// ## 왜 여기만 서버를 다시 부르는가 (P16의 "재평가는 왕복 0" 원칙과의 갈림)
  ///
  /// P16이 세운 원칙은 **"바뀐 게 시계뿐이면 서버를 다시 부르지 않는다"** 였다.
  /// 셀프 체크인 버튼이 그 전형이다 — 창이 열렸다는 사실은 이미 손에 든 `startAt`
  /// 하나로 다시 계산할 수 있고, 예약 자체는 그대로다.
  ///
  /// **Home Work는 그 조건에 해당하지 않는다.** 여기서 날짜는 판정의 입력이 아니라
  /// **어느 문서를 읽고 쓸지 고르는 키**다(`GET/POST /v1/hw-checks?date=`,
  /// 서버 `store.SaveHwCheck`의 `(회원,배정,날짜)` 합성 키). 자정을 넘기면 화면에
  /// 남은 목록은 "낡은 판정"이 아니라 **다른 문서의 내용**이다 — 배정 자체가
  /// 요일 스케줄(`HomeworkScheduleRules.isActiveOn`)로 달라지므로 항목 수까지
  /// 바뀔 수 있다. 로컬 계산으로는 오늘 목록을 만들 방법이 아예 없다.
  ///
  /// 왕복 비용은 이렇게 묶었다:
  ///  · **자정 경계에만** 깨운다(`TimeBoundaryBuilder(atMidnight: true)`) — 폴링 아님.
  ///  · 홈 탭이 **보일 때만**(`TickerMode`) + 앱이 foreground일 때만.
  ///  · 날짜가 실제로 어긋났을 때만(같으면 즉시 반환) — 미래 날짜를 보고 있는
  ///    다른 카드들의 자정 리빌드는 여기까지 오지 않는다.
  ///  · 실패하면 [_rolloverRequestedFor]가 그날치 재시도를 한 번으로 막는다.
  ///
  /// 그래도 못 미친 경우(오프라인·백그라운드 복귀 직전 탭 등)를 위해
  /// [toggleHomework]가 **왕복 0의 최종 방어선**으로 쓰기를 막는다.
  void refreshIfDateRolled() {
    final loaded = state.value?.homeworkDate;
    if (loaded == null) return; // 아직 한 번도 못 읽었다 — 곧 로드가 오늘 값을 채운다.
    final today = DateFmt.todayKst();
    if (loaded == today) return;
    if (_rolloverRequestedFor == today) return;
    _rolloverRequestedFor = today;
    refresh();
  }

  /// 패스 스위처 칩 탭 — 그 코치 기준으로 다음 예약/Home Work를 다시 계산.
  ///
  /// **실패해도 보고 있던 홈을 뺏지 않는다.** 종전엔 실패를 그대로 `AsyncError`에
  /// 넣어서, 칩 한 번 잘못 눌렀다가 네트워크가 흔들리면 **멀쩡하던 홈이 통째로
  /// 사라지고** "다시 시도" 버튼만 남았다. 칩 탭은 부분 갱신이라 "안 바뀌었다"고
  /// 알리면 되지 화면을 치울 이유가 없다.
  ///
  /// 알리는 방법은 이 앱에 이미 있는 규약을 쓴다 — Home Work 토글 실패와 같은
  /// 스낵바 채널([homeworkToggleErrorProvider]).
  Future<void> selectPass(String passId) async {
    final memberId = ref.read(sessionProvider)?.memberId;
    // 세션이 비었으면 리스너가 이미 화면을 내리는 중이다 — 홈의 부분 갱신은 알릴
    // 상대가 없으므로 조용히 끝낸다(촬영 탭과 달리 잃을 바이트가 없다, P64).
    if (memberId == null) return;
    final repo = ref.read(homeRepositoryProvider);
    final result = await repo.loadHome(
      memberId: memberId,
      preferredPassId: passId,
    );
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
      case Err(:final failure):
        // 처음 로딩조차 안 끝난 상태라면 보여줄 게 없으니 종전대로 에러로 간다.
        if (state.value == null) {
          state = AsyncError(failure, StackTrace.current);
          return;
        }
        ref.read(homeworkToggleErrorProvider.notifier).set(failure);
    }
  }

  /// Home Work 체크박스 토글 — 낙관적 업데이트 후 실패 시 롤백.
  /// POST /v1/hw-checks는 done 배열 전체를 요구하므로 같은 hwId 형제 항목을 모아 전송.
  Future<void> toggleHomework(HomeworkItem item) async {
    final current = state.value;
    final memberId = ref.read(sessionProvider)?.memberId;
    // 세션 없음은 위 selectPass와 같은 이유로 조용히 — 낙관적 갱신을 시작하기 전이라
    // 되돌릴 것도 없다.
    if (current == null || memberId == null) return;

    // 오늘 체크 상태를 못 읽었으면 **보내지 않는다**. 형제 항목의 done은 전부
    // 폴백(false)이고 서버는 문서를 통째로 교체하므로(store.SaveHwCheck의 `.Set()`),
    // 여기서 배열을 만들어 보내는 순간 서버의 완료 기록이 조용히 지워진다.
    // 화면(HomeworkChecklistCard)도 잠그지만 뷰모델이 마지막 관문이다.
    if (current.homeworkChecksFailed) {
      ref.read(homeworkToggleErrorProvider.notifier).set(
            // 홈 화면이 "체크 저장에 실패했어요 — {message}"로 감싼다 — 여기서는
            // 사유만 말한다(문장 부호가 겹치지 않게 대시를 다시 쓰지 않는다).
            const RejectedFailure('오늘 체크 상태를 불러오지 못했어요. 아래로 당겨 새로고침해주세요'),
          );
      return;
    }

    // **읽기 시점 날짜 ≠ 지금 날짜면 보내지 않는다** — 위 잠금과 같은 종류의 사고이고
    // (문서 전체 교체), 이쪽이 더 조용하다. 23:50에 홈을 열고 00:05에 한 칸을
    // 체크하면 화면의 목록은 **어제 것**인데 서버가 쓰는 문서는 오늘 것이다:
    // 어제 done 배열이 오늘 문서를 통째로 덮어 오늘 아침에 체크해 둔 기록이 사라지고,
    // 배정이 요일 스케줄로 달라졌으면 항목 수가 맞지 않아 인덱스까지 어긋난다.
    //
    // 정상 흐름에선 여기까지 오지 않는다 — 자정에 홈 화면이
    // [refreshIfDateRolled]로 오늘 목록을 이미 받아 온다. 이건 그게 못 닿은 경우
    // (오프라인·재조회 실패)를 위한 **왕복 0의 최종 방어선**이고, 재조회를 한 번 더
    // 유도해 스스로 풀리게 한다.
    final today = DateFmt.todayKst();
    if (current.homeworkDate != today) {
      refreshIfDateRolled();
      ref.read(homeworkToggleErrorProvider.notifier).set(
            const RejectedFailure('자정이 지나 날짜가 바뀌었어요. 오늘 목록을 다시 불러올게요'),
          );
      return;
    }

    final newDone = !item.done;
    final updatedItems = <HomeworkItem>[
      for (final i in current.homeworkItems)
        if (i.hwId == item.hwId && i.index == item.index) i.copyWith(done: newDone) else i,
    ];
    state = AsyncData(current.copyWith(homeworkItems: updatedItems));

    final siblings = updatedItems.where((i) => i.hwId == item.hwId).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final doneArray = siblings.map((i) => i.done).toList();

    final repo = ref.read(homeRepositoryProvider);
    final result = await repo.submitHomeworkChecks(
      memberId: memberId,
      hwId: item.hwId,
      // 읽기(HomeRepositoryImpl의 배정 필터·GET ?date=)가 **실제로 쓴 그 날짜**를
      // 그대로 되돌려 보낸다 — 시계를 여기서 다시 읽지 않는다. 같은 축(KST)을
      // 쓰는 것만으로는 부족했다: 두 번 읽는 한 그 사이에 자정이 끼면 값이 갈리고,
      // 그게 어제 목록으로 오늘 문서를 덮던 경로였다(위 날짜 가드 · homeworkDate 주석).
      // 위 가드를 통과했으므로 이 값은 오늘과 같다 — 그래도 "읽은 날짜"를 보내는
      // 쪽이 불변식을 코드로 드러낸다.
      date: current.homeworkDate,
      done: doneArray,
    );
    if (result case Ok()) {
      // 기록 탭의 "Home Work 주간 기록"은 같은 hw-checks를 읽는다. 5개 탭이
      // StatefulShellRoute.indexedStack으로 **동시에 mount된 채 유지**되므로
      // (core/router/app_router.dart) 탭을 오가는 것만으로는 AsyncData가 폐기되지
      // 않는다 — 여기서 무효화하지 않으면 홈에서 체크한 뒤 기록 탭이 "0/3"으로
      // 남는다. 성공 시에만 — 실패는 아래에서 역토글로 원상복구된다.
      ref.invalidate(recordsViewModelProvider);
    }
    if (result case Err(:final failure)) {
      // "토글 시점 스냅샷" 복원은 그 사이 성공한 다른 토글까지 되돌린다 →
      // 최신 상태에서 실패한 항목 하나만 원래 값(item.done)으로 역토글.
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(homeworkItems: [
          for (final i in latest.homeworkItems)
            if (i.hwId == item.hwId && i.index == item.index) i.copyWith(done: item.done) else i,
        ]));
      }
      // 실패 사실을 홈 화면 스낵바로 노출(ref.listen 대상).
      ref.read(homeworkToggleErrorProvider.notifier).set(failure);
    }
  }

  /// 다음 예약 카드의 셀프 체크인 버튼 — 예약 특정은 서버가 시간창으로 판정.
  /// 성공 시 해당 예약 id를 기록해 카드 버튼을 "체크인 완료"로 잠그고 홈을 새로고침.
  ///
  /// [scannedToken] = QrScanScreen이 읽어온 QR 원문. 토큰 모양·유효성은 서버가
  /// 판정하므로 여기서 사전 검증하지 않는다(잘못된 QR이면 400 문구를 그대로 노출).
  Future<Result<void>> checkIn({String? scannedToken}) async {
    final repo = ref.read(homeRepositoryProvider);
    final result = await repo.selfCheckIn(scannedToken: scannedToken);
    if (result case Ok()) {
      final bookingId = state.value?.nextBooking?.id;
      if (bookingId != null) {
        ref.read(checkedInBookingIdProvider.notifier).set(bookingId);
      }
      refresh();
    }
    return result;
  }
}

/// Home Work 토글 실패 1회성 알림 — 홈 화면이 listen해 스낵바로 보여준 뒤 clear.
@riverpod
class HomeworkToggleError extends _$HomeworkToggleError {
  @override
  Failure? build() => null;

  void set(Failure failure) => state = failure;
  void clear() => state = null;
}

/// 셀프 체크인에 성공한 예약 id — 다음 예약 카드 버튼을 "체크인 완료"로 비활성.
@riverpod
class CheckedInBookingId extends _$CheckedInBookingId {
  @override
  String? build() => null;

  void set(String bookingId) => state = bookingId;
}
