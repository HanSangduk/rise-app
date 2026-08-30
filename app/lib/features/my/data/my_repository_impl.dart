import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/my/data/my_remote_data_source.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';

class MyRepositoryImpl implements MyRepository {
  const MyRepositoryImpl(
    this._passesApi,
    this._readStaffMap,
    this._remote,
    this._memberApi,
  );

  final PassesApi _passesApi;

  /// 스태프 맵은 [staffMapReaderProvider]를 통해서만 읽는다 — 홈·예약과 같은
  /// 캐시(staffMapProvider)를 공유하고, 실패해도 빈 맵으로 떨어진다(best-effort).
  final StaffMapReader _readStaffMap;
  final MyRemoteDataSource _remote;
  final MemberApi _memberApi;

  @override
  Future<Result<MySummary>> load(String memberId) {
    return guardApi(() async {
      // 이름 해석 실패가 회원권·원장·계약을 통째로 가리지 않게 best-effort
      // (staffMapReaderProvider 주석).
      final staffMap = await _readStaffMap();
      final passDtos = await _passesApi.fetchMyPasses(memberId);
      final passes = passDtos
          .map((p) => PassDetail(
                id: p.id,
                product: p.product,
                trainerId: p.trainerId,
                trainerName: staffMap[p.trainerId]?.name,
                // 계약 v2.0 — 이름은 유지하고 퇴사 여부만 함께(표기는 화면이 정한다).
                trainerInactive: staffMap[p.trainerId]?.isInactive ?? false,
                status: p.status,
                remaining: p.remaining,
                totalSessions: p.totalSessions,
                paidAmount: p.paidAmount,
                validFrom: DateTime.parse(p.validFrom),
                validUntil: DateTime.parse(p.validUntil),
                holds: [
                  for (final h in p.holds)
                    PassHold(from: DateTime.parse(h.from), to: DateTime.parse(h.to), reason: h.reason),
                ],
              ))
          .toList();

      // 원장은 패스별 조회 — best-effort지만 실패를 "내역 없음"으로 위장하지 않는다.
      // 실패한 패스 id를 모아 UI에 넘기고(contractsFailed와 같은 규약), 화면은
      // 빈 상태 문구 대신 "불러오지 못했어요 + 새로고침"을 보여준다.
      final ledgerByPass = <String, List<LedgerEntry>>{};
      final ledgerFailedPassIds = <String>{};
      for (final p in passes) {
        try {
          final dtos = await _remote.fetchLedger(memberId: memberId, passId: p.id);
          final entries = dtos
              .map((d) => LedgerEntry(
                    id: d.id,
                    passId: d.passId,
                    delta: d.delta,
                    reason: LedgerReason.fromWire(d.reason),
                    refBookingId: d.refBookingId,
                    by: d.by,
                    at: DateTime.parse(d.at),
                  ))
              .toList()
            ..sort((a, b) => b.at.compareTo(a.at));
          ledgerByPass[p.id] = entries;
        } catch (_) {
          ledgerByPass[p.id] = const [];
          ledgerFailedPassIds.add(p.id);
        }
      }

      // GET /v1/contracts?member= (v1.1) — 전자계약 목록.
      // best-effort: 계약 조회 실패가 마이 탭 전체(회원권·원장)를 죽이지 않도록
      // ledger/consent와 동일하게 try/catch 후 빈 목록 폴백.
      // 단, 실패를 "계약 없음"으로 위장하지 않게 플래그로 UI에 구분 전달.
      var contracts = const <ContractItem>[];
      var contractsFailed = false;
      try {
        final contractDtos = await _remote.fetchContracts(memberId);
        contracts = contractDtos
            .map((d) => ContractItem(
                  id: d.id,
                  passId: d.passId,
                  product: d.product,
                  paidAmount: d.paidAmount,
                  status: d.status,
                  sentAt: d.sentAt == null ? null : DateTime.tryParse(d.sentAt!),
                  // 최초 발송 증적 — {{계약 체결일}} 렌더의 미서명 폴백(계약서doc :781).
                  firstSentAt: d.firstSentAt == null ? null : DateTime.tryParse(d.firstSentAt!),
                  signedAt: d.signedAt == null ? null : DateTime.tryParse(d.signedAt!),
                  pdfPath: (d.pdfPath == null || d.pdfPath!.isEmpty) ? null : d.pdfPath,
                  // v2.18 문서 스냅샷 — 빈 값은 빈 값 그대로(스냅샷 유무 판정은
                  // ContractItem.hasDocumentSnapshot 몫).
                  templateVersion: d.templateVersion,
                  vars: d.vars,
                  // P44 체결 증적 — 서명 IP·문서 해시는 빈 문자열을 null로 접는다
                  // (pdfPath와 같은 규약: 빈 값 행을 그리지 않는다). 서명 이미지
                  // 2필드는 빈 값 그대로 — 유무 판정은 hasSignatureImage 몫.
                  signerIp: (d.signerIp == null || d.signerIp!.isEmpty) ? null : d.signerIp,
                  sha256: (d.sha256 == null || d.sha256!.isEmpty) ? null : d.sha256,
                  signaturePng: d.signaturePng,
                  signatureSha256: d.signatureSha256,
                  // 위약금율은 계약 상세에서 보여준다 — 회원이 나중에 "해지하면
                  // 얼마 떼이나"를 다시 확인할 수 있어야 한다. 종전엔 DTO까지만
                  // 받고 여기서 버려 화면까지 오지 못했다.
                  penaltyRate: d.penaltyRate,
                ))
            .toList();
      } catch (_) {
        // 계약 목록만 비우고 실패 표시 — 나머지 마이 탭 정보는 그대로 노출.
        contractsFailed = true;
      }

      // GET /v1/payments?member= — 내 결제·분할 내역. 다른 조회와 같은 best-effort:
      // 실패를 "결제 없음"으로 위장하면 **미납이 있는 회원에게 없다고 말하게 된다**.
      var payments = const <PaymentItem>[];
      var paymentsFailed = false;
      try {
        final dtos = await _remote.fetchPayments(memberId);
        payments = dtos
            .map((d) => PaymentItem(
                  id: d.id,
                  passId: d.passId,
                  method: d.method,
                  total: d.total,
                  installments: d.installments
                      .map((i) => InstallmentItem(
                            due: i.due,
                            amount: i.amount,
                            paidAt: i.paidAt == null ? null : DateTime.tryParse(i.paidAt!),
                            waivedAt: i.waivedAt == null ? null : DateTime.tryParse(i.waivedAt!),
                          ))
                      .toList(),
                ))
            .toList();
      } catch (_) {
        paymentsFailed = true;
      }

      // 동의 상태 조회도 best-effort지만, **실패를 "미동의"로 위장하면 안 된다**:
      // 아래 기본값(false/false)이 그대로 동의 시트에 실려 저장되면 서버가
      // sensitive true→false를 철회로 보고 revoked_at을 남기고(P8 —
      // normalizeConsentTransition), 인바디·체형사진 저장이 그 즉시 잠긴다.
      // 회원이 토글을 건드리지도 않은 채 법적 기록이 남는 유일한 경로라
      // contractsFailed와 같은 규약으로 플래그를 세워 **저장 자체를 막는다**.
      var consent = const ConsentState(general: false, sensitive: false);
      var consentFailed = false;
      try {
        final profile = await _memberApi.fetchMyProfile();
        final c = profile.consent;
        if (c != null) {
          consent = ConsentState(
            general: c.general,
            sensitive: c.sensitive,
            signedAt: c.signedAt == null ? null : DateTime.tryParse(c.signedAt!),
            revokedAt: c.revokedAt == null ? null : DateTime.tryParse(c.revokedAt!),
          );
        }
        // c == null은 실패가 아니다 — 서버 Member.Consent는 값 타입(omitempty 없음)이라
        // 항상 실려 온다. 여기를 "모름"으로 취급하면 consent 키를 안 주는 서버에서
        // 회원이 **영원히 동의할 수 없게** 되므로 기본값(미동의)을 그대로 쓴다.
      } catch (_) {
        consentFailed = true;
      }

      return MySummary(
        passes: passes,
        ledgerByPass: ledgerByPass,
        contracts: contracts,
        consent: consent,
        payments: payments,
        paymentsFailed: paymentsFailed,
        contractsFailed: contractsFailed,
        ledgerFailedPassIds: ledgerFailedPassIds,
        consentFailed: consentFailed,
      );
    });
  }

  @override
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) {
    return guardApi(() => _remote.requestHold(
          passId: passId,
          from: DateFmt.isoDate(from),
          to: DateFmt.isoDate(to),
          reason: reason,
        ));
  }

  @override
  Future<Result<void>> resumeHold(String passId) => guardApi(() => _remote.resumeHold(passId));

  @override
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) {
    return guardApi(() => _memberApi.updateConsent(memberId: memberId, general: general, sensitive: sensitive));
  }

  @override
  Future<Result<void>> signContract(String contractId, {String? signaturePng}) =>
      guardApi(() => _remote.signContract(contractId, signaturePng: signaturePng));

  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() {
    return guardApi(() async {
      final json = await _remote.deleteAccount();
      // 파싱은 **절대 던지지 않는다**(AccountDeletionSummary.fromJson 전 필드 옵셔널).
      // 여기까지 왔다면 서버는 이미 계정을 지웠다 — 요약 숫자 하나 때문에 회원에게
      // "실패했어요"라고 말하면, 다시 눌러도 이제 404만 돌아온다.
      return AccountDeletionSummary.fromJson(json);
    });
  }
}
