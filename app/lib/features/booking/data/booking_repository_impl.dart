import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/booking/data/booking_remote_data_source.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_repository.dart';

class BookingRepositoryImpl implements BookingRepository {
  const BookingRepositoryImpl(this._remote, this._bookingsApi, this._readStaffMap);

  final BookingRemoteDataSource _remote;
  final BookingsApi _bookingsApi;

  /// 스태프 맵은 [staffMapReaderProvider]를 통해서만 읽는다 — 홈·마이와 같은
  /// 캐시(staffMapProvider)를 공유하고, 실패해도 빈 맵으로 떨어진다(best-effort).
  final StaffMapReader _readStaffMap;

  @override
  Future<Result<List<Slot>>> loadSlots(DateTime date) {
    return guardApi(() async {
      final dtos = await _remote.fetchSlots(DateFmt.isoDate(date));
      return dtos
          .map((d) => Slot(
                slotKey: d.slotKey,
                capacity: d.capacity,
                teams: d.teams
                    .map((t) => SlotTeam(
                          bookingId: t.bookingId,
                          trainerId: t.trainerId,
                          memberId: t.memberId,
                          kind: t.kind,
                        ))
                    .toList(),
              ))
          .toList();
    });
  }

  @override
  Future<Result<List<MyBooking>>> loadMyBookings(String memberId) {
    return guardApi(() async {
      // 이름 해석 실패가 "내 예약" 목록을 통째로 가리지 않게 best-effort
      // (staffMapReaderProvider 주석).
      final staffMap = await _readStaffMap();
      final dtos = await _bookingsApi.fetchMyBookings(memberId);
      return dtos
          .where((d) => d.status != 'cancelled')
          .map((d) => MyBooking(
                id: d.id,
                slotKey: d.slotKey,
                // 예약 예산 판정(P13 H1)이 패스별로 confirmed 건수를 세려면 필요하다
                // — DTO는 예전부터 파싱했고 여기서만 버려지고 있었다.
                // (`GET /v1/bookings`는 회원 응답에서도 pass_id를 마스킹하지 않는다.)
                passId: d.passId,
                trainerId: d.trainerId,
                // 계약 v2.0 — 퇴사한 코치의 예약이라도 이름 해석은 유지한다
                // (필터링은 "새 예약 선택지"에만 적용, 기존 예약엔 적용 안 함).
                trainerName: staffMap[d.trainerId]?.name,
                trainerInactive: staffMap[d.trainerId]?.isInactive ?? false,
                kind: d.kind,
                status: d.status,
                recurringId: d.recurringId,
              ))
          .toList();
    });
  }

  @override
  Future<Result<void>> book({
    required String slotKey,
    required String memberId,
    required String passId,
  }) {
    return guardApi(() => _remote.book(slotKey: slotKey, memberId: memberId, passId: passId));
  }

  @override
  Future<Result<void>> cancel(String bookingId) => guardApi(() => _remote.cancel(bookingId));

  @override
  Future<Result<void>> createRecurring({
    required String memberId,
    required String trainerId,
    required String passId,
    required List<String> days,
    required int hour,
    DateTime? until,
  }) {
    return guardApi(() => _remote.createRecurring(
          memberId: memberId,
          trainerId: trainerId,
          passId: passId,
          days: days,
          hour: hour,
          until: until == null ? null : DateFmt.isoDate(until),
        ));
  }

  @override
  Future<Result<void>> deleteRecurring(String recurringId) =>
      guardApi(() => _remote.deleteRecurring(recurringId));
}
