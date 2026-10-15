import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/booking/data/booking_remote_data_source.dart';
import 'package:rise_member/features/booking/data/booking_repository_impl.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_repository.dart';
import 'package:rise_member/features/booking/domain/booking_rules.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

part 'booking_view_model.g.dart';

@riverpod
BookingRepository bookingRepository(Ref ref) {
  final dio = ref.watch(dioProvider);
  return BookingRepositoryImpl(
    BookingRemoteDataSource(dio),
    ref.watch(bookingsApiProvider),
    // StaffDirectory 직접 주입 금지 — 캐시(staffMapProvider)를 우회하게 된다.
    ref.watch(staffMapReaderProvider),
  );
}

/// 날짜 스트립에서 선택된 날짜(기본 오늘).
///
/// ## 이 초기값은 **앱 프로세스 수명 내내 다시 계산되지 않는다** (P17)
///
/// 예약 탭은 `StatefulShellRoute.indexedStack`에 상주해서(`core/router/app_router.dart`)
/// 탭을 떠나도 구독이 끊기지 않는다 — autoDispose provider지만 실제로는 폐기되지
/// 않으므로 [build]는 첫 진입 때 딱 한 번 돈다. 자정을 넘겨도 여기 담긴 "오늘"은
/// 어제인 채로 남고, 회원이 보는 건 이렇다:
///
///  · `DateStrip`은 매 build마다 `todayKst()`부터 14일을 새로 그린다 — 목록에 어제가
///    없으니 **선택된 칩이 하나도 없다.**
///  · 뷰모델은 어제 날짜로 슬롯을 로드하고, `SlotList`는 지난 시각을 "지남"으로
///    그린다 — **13칸이 전부 "지남"**.
///
/// 회원 입장에서 예약 탭이 통째로 죽은 화면이 된다. 앱을 껐다 켜기 전엔 안 풀린다.
///
/// ## 처방 — 자정에 [rolloverToToday]로 **당긴다**
///
/// 되돌리지 않고 **앞으로만** 민다. 과거 날짜를 고를 경로가 없으므로(스트립은 오늘부터
/// 14일) "선택 날짜가 오늘보다 과거"라는 상태는 자정을 넘겼다는 뜻 하나뿐이고,
/// 회원이 고른 미래 날짜는 그대로 둔다.
///
/// 트리거는 화면이 쥔다(`BookingScreen`의 `TimeBoundaryBuilder(atMidnight: true)`) —
/// provider 안에 타이머를 두면 다른 탭에 있을 때도, 앱이 백그라운드일 때도 돈다.
/// 그 판단(비활성 탭 게이팅 · 앱 재개 재평가)은 이미 그 위젯에 들어 있다.
@riverpod
class SelectedBookingDate extends _$SelectedBookingDate {
  @override
  // 기본값은 센터(KST) 기준 오늘 — DateStrip이 그리는 14일 목록과 같은 기준이라야
  // 해외 체류·기기 시계 오설정에서도 첫 칩이 선택된 채로 열린다(DateFmt 시간축 규약).
  DateTime build() => DateFmt.todayKst();

  void select(DateTime date) => state = DateTime(date.year, date.month, date.day);

  /// 자정을 넘겨 선택 날짜가 **과거**가 됐으면 오늘로 당긴다.
  ///
  /// 이미 오늘 이후면 아무 일도 하지 않는다 — 상태를 건드리지 않으므로 뷰모델
  /// 재빌드(= 슬롯 재조회)도 일어나지 않는다. 미래 날짜를 보고 있던 회원의 화면은
  /// 자정에도 그대로다. 여러 번 불러도 결과가 같다(멱등).
  void rolloverToToday() {
    final today = DateFmt.todayKst();
    if (state.isBefore(today)) state = today;
  }
}

/// "내 코치 / 전체 코치" 토글 — 목업 fMy/fAll. 슬롯은 그대로 두고 클라이언트에서 필터.
@riverpod
class ShowMyCoachOnly extends _$ShowMyCoachOnly {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

/// 예약 탭 — 홈의 패스 스위처에서 선택된 패스를 "내 코치" 기준으로 재사용.
@riverpod
class BookingViewModel extends _$BookingViewModel {
  @override
  Future<BookingScreenData> build() async {
    final memberId = ref.watch(sessionProvider)?.memberId;
    if (memberId == null) {
      // 셸이 떠 있는 채 세션이 비었다 — 리스너가 이동 중이라 문구가 아닌 타입만 낸다(P64).
      throw const SessionGoneFailure();
    }

    final date = ref.watch(selectedBookingDateProvider);
    final home = await ref.watch(homeViewModelProvider.future);

    final repo = ref.watch(bookingRepositoryProvider);
    final serverSlots = _unwrap(await repo.loadSlots(date));
    final bookings = _unwrap(await repo.loadMyBookings(memberId));

    // 빈 시간대 합성(P04 HIGH) — 서버는 예약이 있던 슬롯만 주므로, 센터 운영시간의
    // 빈 슬롯을 정책 용량(slot_capacity)으로 합성해 병합한다(slot_key 기준, 서버 우선).
    // 이 provider는 조회 실패 시 fallback을 반환하고 절대 throw하지 않는다.
    //
    // 운영시간도 **정책 실값**이다(policy.open_hour/close_hour) — 예전엔 규칙 파일에
    // 9·21이 상수로 박혀 있어, 06시에 열거나 23시에 닫는 센터의 회원은 실제 영업
    // 중인 시간대를 앱에서 볼 수조차 없었다. 구버전 서버(필드 부재)는 정책 provider가
    // 9·21로 해석하므로 이 줄의 동작은 종전과 한 칸도 다르지 않다.
    final policy = await ref.watch(centerPolicyProvider.future);
    final slots = BookingRules.mergeWithOpenHours(
      date: date,
      serverSlots: serverSlots,
      capacity: policy.slotCapacity,
      openHour: policy.openHour,
      closeHour: policy.closeHour,
    );

    return BookingScreenData(
      selectedDate: date,
      slots: slots,
      myBookings: bookings,
      myPasses: [
        for (final p in home.passes)
          BookablePass(
            passId: p.id,
            trainerId: p.trainerId,
            trainerName: p.trainerName,
            trainerInactive: p.trainerInactive,
            // 담당 코치 휴무일 — 홈 repository가 스태프 맵에서 이미 해석해 둔 값
            // (이름·퇴사 여부와 같은 출처·같은 시점). 휴무일 슬롯은 서버가 400으로
            // 거부하므로 사전 차단한다(BookingRules → TrainerOffday).
            trainerOffdays: p.trainerOffdays,
            product: p.product,
            validFrom: p.validFrom,
            validUntil: p.validUntil,
            status: p.status,
            // 잔여 회차 — 서버가 예약마다 재계산해 0이면 400으로 거부한다. 예전엔
            // 이 매핑에서 통째로 버려서 잔여 0에도 "예약" 버튼이 살아 있었다.
            remaining: p.remaining,
            // 이미 잡아 둔 confirmed 예약 수 — 잔여만으로는 부족하다. 서버 예산은
            // `remaining − open`이고(P13 H1) 잔여는 완료 시점에만 줄어드므로,
            // 이 값을 빼지 않으면 잔여 2회 패스에 세 번째 예약 버튼이 살아 있다.
            //
            // 방금 위에서 로드한 **같은 예약 목록**으로 센다 — 서버가 보는
            // `ListBookingsByMember`와 같은 모집단(회원 전체·날짜 필터 없음)이라
            // 별도 조회가 필요 없고, 예약/취소 후 이 provider가 통째로 다시
            // 빌드되므로 두 값이 갈릴 틈도 없다.
            openBookings: BookingRules.countOpenBookings(bookings, p.id),
            // 일시정지 구간 — 홀드 기간에 걸친 슬롯을 예약 전에 차단(BookingRules).
            holds: p.holds,
          ),
      ],
      primaryPassId: home.selectedPassId,
    );
  }

  T _unwrap<T>(Result<T> r) => switch (r) {
        Ok<T>(:final value) => value,
        Err<T>(:final failure) => throw failure,
      };

  void selectDate(DateTime date) => ref.read(selectedBookingDateProvider.notifier).select(date);

  void refresh() => ref.invalidateSelf();

  Future<Result<void>> book({required String slotKey, required String passId}) async {
    final memberId = ref.read(sessionProvider)?.memberId;
    if (memberId == null) return const Err(SessionGoneFailure());

    final repo = ref.read(bookingRepositoryProvider);
    final result = await repo.book(slotKey: slotKey, memberId: memberId, passId: passId);
    if (result case Ok()) {
      // 홈의 "다음 예약" 카드도 같은 데이터를 보므로 함께 갱신(크로스탭 stale 방지).
      ref.invalidate(homeViewModelProvider);
      // 마이 탭의 회원권 카드(예약 가능 판정에 쓰는 열린 예약 수)도 같은 사실을 본다(P73).
      ref.invalidate(myViewModelProvider);
      refresh();
    }
    return result;
  }

  Future<Result<void>> cancel(String bookingId) async {
    final repo = ref.read(bookingRepositoryProvider);
    final result = await repo.cancel(bookingId);
    if (result case Ok()) {
      // 취소 직후 홈 "다음 예약" 카드가 낡은 예약을 계속 보여주지 않게 동반 갱신.
      ref.invalidate(homeViewModelProvider);
      // 컷오프 뒤 취소는 원장에 -1(또는 유예)을 남기고, 취소 확인 다이얼로그가 "차감 여부는
      // 마이 탭 이용내역에서 확인할 수 있어요"라고 **약속**한다. 마이 탭을 새로고침하지 않으면
      // 그 약속을 따라간 회원이 차감 전 잔여·이용내역을 본다(P73).
      ref.invalidate(myViewModelProvider);
      refresh();
    }
    return result;
  }
}
