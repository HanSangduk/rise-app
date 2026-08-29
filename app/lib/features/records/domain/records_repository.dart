import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

abstract interface class RecordsRepository {
  /// 전부 실 API(v1.4): 수업 기록(GET /v1/workout-logs?member=) +
  /// Home Work 주간 집계(GET /v1/hw-checks?member= → HomeworkWeekRules) +
  /// 인바디(GET /v1/inbody?member=) + 체형사진(GET /v1/body-photos?member=).
  Future<Result<RecordsData>> load(String memberId);

  /// 인바디 수기 입력 저장(POST /v1/inbody) — 회원 본인 기록만.
  ///
  /// 요청 바디는 계약의 8필드 그대로다. `source`는 **보내지 않는다**
  /// (서버가 Principal로 판정 · DisallowUnknownFields).
  Future<Result<void>> createInbody({
    required String memberId,
    required InbodyDraft draft,
  });

  /// 인바디 기록 삭제(DELETE /v1/inbody/{id}).
  ///
  /// 수정(PUT)은 만들지 않는다 — 삭제 후 재입력으로 충분하고 API 면적이 절반이다.
  /// 이 경로가 없으면 회원의 오입력이 영구 확정되므로 입력 폼과 **한 묶음**이다.
  Future<Result<void>> deleteInbody(String id);
}
