import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/dto/booking_dto.dart';
import 'package:rise_member/core/network/dio_client.dart';

part 'bookings_api.g.dart';

/// API계약 v1.1로 확정됨: `GET /v1/bookings?member=&from=` (앱 가정 승인 —
/// 내 예약 목록). 홈(다음 예약)과 예약 탭(내 예약 리스트)이 공유한다.
class BookingsApi {
  const BookingsApi(this._dio);
  final Dio _dio;

  Future<List<BookingDto>> fetchMyBookings(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/bookings',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => BookingDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

@riverpod
BookingsApi bookingsApi(Ref ref) => BookingsApi(ref.watch(dioProvider));
