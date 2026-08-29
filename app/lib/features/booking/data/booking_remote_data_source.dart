import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/slot_dto.dart';

class BookingRemoteDataSource {
  const BookingRemoteDataSource(this._dio);
  final Dio _dio;

  /// GET /v1/slots?date= → [Slot] (용량·팀).
  Future<List<SlotDto>> fetchSlots(String date) async {
    final res = await _dio.get<List<dynamic>>('/v1/slots', queryParameters: {'date': date});
    return (res.data ?? [])
        .map((e) => SlotDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/bookings {slot_key, member_id, pass_id} — 트랜잭션은 서버 책임(P35).
  Future<void> book({
    required String slotKey,
    required String memberId,
    required String passId,
  }) {
    return _dio.post<void>('/v1/bookings', data: {
      'slot_key': slotKey,
      'member_id': memberId,
      'pass_id': passId,
    });
  }

  /// DELETE /v1/bookings/{id} — 컷오프(24h) 검사는 서버.
  Future<void> cancel(String bookingId) => _dio.delete<void>('/v1/bookings/$bookingId');

  /// POST /v1/recurrings — 고정 스케줄(P47).
  Future<void> createRecurring({
    required String memberId,
    required String trainerId,
    required String passId,
    required List<String> days,
    required int hour,
    String? until,
  }) {
    return _dio.post<void>('/v1/recurrings', data: {
      'member_id': memberId,
      'trainer_id': trainerId,
      'pass_id': passId,
      'days': days,
      'hour': hour,
      if (until != null) 'until': until,
    });
  }

  Future<void> deleteRecurring(String recurringId) =>
      _dio.delete<void>('/v1/recurrings/$recurringId');
}
