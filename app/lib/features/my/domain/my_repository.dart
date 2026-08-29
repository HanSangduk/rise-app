import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

abstract interface class MyRepository {
  Future<Result<MySummary>> load(String memberId);

  /// POST /v1/passes/{id}/hold {from,to,reason}.
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  });

  /// POST /v1/passes/{id}/resume.
  Future<Result<void>> resumeHold(String passId);

  /// PUT /v1/members/{id} {consent:{...}}.
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  });

  /// POST /v1/contracts/{id}/sign (v1.4 — 회원 자체서명, sent→signed 전이).
  Future<Result<void>> signContract(String contractId);

  /// DELETE /v1/me (v2.11 — 회원탈퇴). **되돌릴 수 없다.**
  ///
  /// 성공하면 이 계정으로는 더 이상 어떤 API도 부를 수 없다(서버가 UserIndex와 Firebase
  /// 계정을 함께 지운다). 호출한 화면은 결과를 받은 즉시 로그아웃하고 로그인으로 나가야 한다 —
  /// 남아 있는 화면의 어떤 새로고침도 이제 401/403으로만 끝난다.
  Future<Result<AccountDeletionSummary>> deleteAccount();
}
