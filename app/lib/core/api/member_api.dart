import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/network/dio_client.dart';

part 'member_api.g.dart';

/// GET /v1/members?trainer=&q= — API계약_v1.md: "역할 스코프 자동(트레이너=담당만)".
/// role=member로 인증된 요청은 쿼리 없이 호출하면 서버가 본인 레코드만 스코프해서
/// 돌려준다고 해석(회원 목록 API가 회원 자신에게는 "내 프로필 조회"로 재사용됨).
/// PUT /v1/members/{id}로 동의(consent) 등 부분 업데이트.
class MemberApi {
  const MemberApi(this._dio);
  final Dio _dio;

  Future<MemberDto> fetchMyProfile() async {
    final res = await _dio.get<List<dynamic>>('/v1/members');
    final list = res.data ?? [];
    if (list.isEmpty) {
      throw StateError('회원 정보를 찾을 수 없어요');
    }
    return MemberDto.fromJson(list.first as Map<String, dynamic>);
  }

  Future<void> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) {
    return _dio.put<void>('/v1/members/$memberId', data: {
      'consent': {'general': general, 'sensitive': sensitive},
    });
  }
}

@riverpod
MemberApi memberApi(Ref ref) => MemberApi(ref.watch(dioProvider));

/// 내 프로필(동의 상태 등) — 체형 분석 촬영 전 동의 확인, 마이 탭 동의 토글에서 공용.
@riverpod
Future<MemberDto> myProfile(Ref ref) => ref.watch(memberApiProvider).fetchMyProfile();
