import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/my/domain/ledger_summary.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/contract_body.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_document_view.dart';

/// 계약 상세 열람.
///
/// 종전에는 **서명한 순간 계약을 다시 볼 길이 사라졌다** — `sent` 행만 서명 시트로
/// 열리고 `signed`/`draft`/`voided`는 배지만 있는 죽은 행이었다. 회원이 얼마를 내고
/// 무엇에 동의했는지 나중에 확인할 수 없는 건, 돈이 오간 계약에서는 그냥 결함이다.
///
/// **없는 걸 있는 척하지 않는다.** 서버 Contract는 지금 상태·메타데이터만 들고 있고
/// 계약 본문 PDF(`pdf_path`)는 연동 전이라 늘 비어 있다(domain/contract.go 주석).
/// 그래서 가진 값(상품·금액·위약금율·발송일·서명일)은 다 보여주되, 본문이 없다는
/// 사실도 숨기지 않고 적는다 — "PDF 보기" 같은 눌러도 안 되는 버튼을 만드느니 낫다.
///
/// P39(§D ⑥): 문서 스냅샷(template_version+vars, v2.18)이 있는 계약은 "계약서 본문"
/// 섹션을 열어 서명 당시 문서를 그대로 재현한다([별지] 해지 신청서 포함, §D ⑦).
/// 스냅샷 없는 레거시는 위 문구·화면 그대로다. PDF 안내 줄은 스냅샷이 있어도 남는다 —
/// 화면 열람(전자문서법 §4의2 요건 충족)과 원본 **파일**의 유무는 다른 사실이고,
/// 파일이 없다는 말은 여전히 참이다(§D ③).
Future<void> showContractDetailSheet(
  BuildContext context, {
  required ContractItem contract,
  double? penaltyRate,
}) {
  return showRiseSheet<void>(
    context,
    builder: (_) => _ContractDetailSheet(contract: contract, penaltyRate: penaltyRate),
  );
}

class _ContractDetailSheet extends StatefulWidget {
  const _ContractDetailSheet({required this.contract, this.penaltyRate});

  final ContractItem contract;

  /// 계약 생성 시점에 스냅샷된 위약금율(0~1). 서버가 안 내려주면 null —
  /// 그때는 **행을 아예 빼서** 0%로 오해하게 만들지 않는다.
  final double? penaltyRate;

  @override
  State<_ContractDetailSheet> createState() => _ContractDetailSheetState();
}

class _ContractDetailSheetState extends State<_ContractDetailSheet> {
  /// 본문 표시 판정(P39) — 서명 시트와 같은 게이트를 탄다(contract_body.dart).
  /// 스냅샷 없는 레거시는 첫 프레임부터 None이라 오늘 화면 그대로다.
  ContractBodyState _body = const ContractBodyLoading();
  bool _bodyResolveStarted = false;

  /// "계약서 본문" 접힘 상태 — 기본 접힘(§D ⑥ "본문 보기"를 **열어** 렌더한다).
  /// 메타(금액·상태·날짜)가 먼저고, 전문은 열어 읽는 것.
  bool _bodyOpen = false;

  /// 서명 이미지 바이트(P44) — base64는 initState에서 **한 번만** 디코드한다.
  /// 깨진 인코딩이면 null: 가짜 이미지를 그리느니 블록 자체를 만들지 않는다
  /// (레거시의 빈 값과 같은 "없음" 경로 — 정직 규약).
  Uint8List? _signatureBytes;

  @override
  void initState() {
    super.initState();
    if (widget.contract.hasSignatureImage) {
      try {
        _signatureBytes = base64Decode(widget.contract.signaturePng);
      } catch (_) {
        _signatureBytes = null;
      }
    }
    if (!widget.contract.hasDocumentSnapshot) {
      _body = const ContractBodyNone();
      _bodyResolveStarted = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bodyResolveStarted) return;
    _bodyResolveStarted = true;
    // DefaultAssetBundle 경유 — 운영은 rootBundle 폴백, 테스트는 가짜 번들 주입
    // (서명 시트와 같은 배선이어야 "서명 때 본 문서 = 나중에 재현되는 문서").
    resolveContractBody(bundle: DefaultAssetBundle.of(context), contract: widget.contract)
        .then((resolved) {
      if (!mounted) return;
      setState(() => _body = resolved);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contract;
    // 패턴 B(center_coaches_sheet) — 시트 전체가 상한(화면 80%) 안에서 스크롤한다.
    // P44 체결 정보(서명 계약은 최대 7행)가 더해지며 고정 Column의 높이 예산이
    // 작은 화면(SE 667dp)에서 넘치게 됐다 — 접거나 줄이는 대신 하우스의 긴 시트
    // 패턴으로 전부 보여준다(입증 자료를 접어 숨기지 않는다).
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${c.product} 계약',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                _headline(c),
                style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  children: [
                    _Row('상품', c.product),
                    // 분할로 내는 중이면 지금까지 낸 돈과 다르다 — 회차 단가·위약금의 기준값이다.
                    _Row('계약가', MoneyFormat.won(c.paidAmount)),
                    _Row('상태', c.statusLabel),
                    if (widget.penaltyRate != null)
                      _Row('위약금율(계약가 기준)',
                          '${(widget.penaltyRate! * 100).toStringAsFixed(widget.penaltyRate! * 100 % 1 == 0 ? 0 : 1)}%'),
                    // P44 마감 리뷰: 전 행 KST 통일 — 문서 체결일·체결 정보와 같은 시간축.
                    if (c.sentAt != null) _Row('발송일', DateFmt.isoDate(DateFmt.toKst(c.sentAt!))),
                    if (c.signedAt != null) _Row('서명일', DateFmt.isoDate(DateFmt.toKst(c.signedAt!))),
                  ],
                ),
              ),
              // 계약서 본문(P39 §D ⑥) — 스냅샷 있는 계약만 행이 생긴다. 레거시는 아래
              // PDF 문구까지 오늘 화면 그대로다(§D ⑥ "지금 문구를 그대로 유지").
              ..._bodySection(context),
              // 체결 정보(P44 결정 7) — signed 전용. 문서 아래, PDF 안내 위.
              if (c.isSigned) ...[
                const SizedBox(height: 10),
                _ConclusionInfo(contract: c),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.line.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  c.pdfPath == null
                      ? '계약서 원본 파일은 아직 앱에 올라와 있지 않아요 — 센터에 요청하면 보내드려요.'
                      : '계약서 원본이 센터에 보관돼 있어요 — 사본이 필요하면 센터에 요청해주세요.',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              RiseButton(
                label: '닫기',
                style: RiseButtonStyleKind.outline,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "계약서 본문" 영역(§D ⑥) — 판정 갈래별 위젯 목록. 읽기 전용이라 끝-스크롤
  /// 게이트는 없다(그건 서명 시트만의 것, §D ⑤).
  List<Widget> _bodySection(BuildContext context) {
    switch (_body) {
      case ContractBodyNone() || ContractBodyLoading():
        return const [];

      case ContractBodyReady(:final document):
        return [
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => setState(() => _bodyOpen = !_bodyOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '계약서 본문',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    _bodyOpen ? '접기' : '보기',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.brand, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          if (_bodyOpen) ...[
            const SizedBox(height: 4),
            // 서명 당시 문서의 재현(D-4) — [별지] 해지 신청서도 본문과 나란히 이 안에
            // 있다(§D ⑦ — 별지가 본문에서 떨어지면 그 자체로 기재사항 누락).
            // 화면 50% 상한 + 내부 스크롤 — 시트 전체가 스크롤(패턴 B)이 된 P44부터
            // Flexible은 불가하다(스크롤 뷰 안은 높이가 무한이라 flex가 성립 안 한다).
            // 상한은 그대로 살아 전문이 화면을 통째로 먹지 않는다.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  // 서명란 표 직하단 도킹 블록(P44 결정 4) — 서명 이미지가 있는
                  // 계약만. 렌더된 문서는 서명 당시 그대로고, 이미지는 뷰가 얹는다.
                  child: ContractDocumentView(
                    document: document,
                    signatureBlock: _buildSignatureBlock(),
                  ),
                ),
              ),
            ),
          ],
        ];

      case ContractBodyNeedsAppUpdate():
        // 미지 버전 — 렌더하지 않는다(§D ④ :916-917). 서명 시트와 같은 문구.
        return const [
          SizedBox(height: 10),
          _BodyNotice('새 계약서 양식입니다 — 앱을 업데이트하면 전문을 열람할 수 있어요'),
        ];

      case ContractBodyUnavailable():
        // 스냅샷은 있는데 그릴 수 없다 — 사실대로 한 줄(P33 정직 규약). 사본 경로는
        // 바로 아래 PDF 안내 줄이 이미 말하고 있다.
        return const [
          SizedBox(height: 10),
          _BodyNotice('계약서 전문을 표시할 수 없어요'),
        ];
    }
  }

  /// 서명란 직하단 도킹 블록(P44 결정 4) — 서명 이미지 + "회원 서명" 라벨 + 서명일.
  /// 센터 측은 표 안 "(인)" 텍스트 유지 — 사전 날인 직인 이미지는 업로드 인프라가
  /// 필요해 후속이다(결정 4). 이미지 없는 계약(레거시·체크 동의 서명)은 null —
  /// 문서는 오늘 그대로다.
  Widget? _buildSignatureBlock() {
    final bytes = _signatureBytes;
    if (bytes == null) return null;
    // P44 마감 리뷰 M: signed에만 도킹한다 — 서버 규약상 미서명+서명 이미지는 생산 불가지만,
    // DTO는 관용 파싱이라 손상·적대 응답이 미체결 문서에 "회원 서명"을 그릴 수 있었다.
    // 없는 체결을 그려 보이는 것은 거짓 신호다(P33 규약).
    if (widget.contract.status != 'signed') return null;
    final signedAt = widget.contract.signedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '회원 서명',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
              ),
              const Spacer(),
              if (signedAt != null)
                // 서버 기록은 UTC 절대 시각 — 표기는 센터(KST) 벽시계로 환산한다.
                Text(
                  '서명일 ${DateFmt.isoDate(DateFmt.toKst(signedAt))}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 투명 배경 PNG — 문서 배경 위에 잉크만 앉는다. base64는 통과했지만
          // PNG가 아닌 데이터면 그리지 않고 접는다(오류 상자를 계약 문서 안에
          // 그리지 않는다 — 가짜도, 시끄러운 깨짐도 아닌 "없음").
          Align(
            alignment: Alignment.centerLeft,
            child: Image.memory(
              bytes,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  String _headline(ContractItem c) => switch (c.status) {
        'signed' => c.signedAt == null
            ? '서명이 완료된 계약이에요'
            : '${DateFmt.isoDate(DateFmt.toKst(c.signedAt!))}에 서명한 계약이에요',
        'draft' => '센터가 작성 중이에요 — 발송되면 서명할 수 있어요',
        'voided' => '환불로 무효 처리된 계약이에요',
        _ => '계약 내용이에요',
      };
}

/// 체결 정보(P44 결정 7) — 업계 감사추적인증서 코어 필드 중 **실보유분만**.
///
/// 캡션은 "입증 자료"까지만 말한다 — **법정 추정력 주장 금지**(결정 7): 현행
/// 전자서명법·전자문서법 어디에도 이런 기록에 대한 추정 조항이 없다(공인전자문서센터
/// §31조의7만 예외). 우리 해시·기록은 체결 사실을 입증하는 수단이라는 사실 그대로만.
///
/// 없는 필드는 행을 만들지 않는다(지어내지 않기) — 레거시(스냅샷·서명 이미지 없음)는
/// 서명 일시·IP만 남는다. 두 해시 행의 라벨이 역할 분리를 명시한다(결정 3:
/// 문서 해시 = send 확정 내용 봉인 ↔ 서명 이미지 해시 = 서명 행위 증적).
class _ConclusionInfo extends StatelessWidget {
  const _ConclusionInfo({required this.contract});
  final ContractItem contract;

  /// 해시는 앞 12자만 — 전체 64자는 행을 깨고, 대조 용도로는 접두가 관행이다
  /// (전체 대조가 필요한 분쟁 국면은 서버 원본으로 한다).
  String _hash12(String h) => h.length <= 12 ? h : '${h.substring(0, 12)}…';

  @override
  Widget build(BuildContext context) {
    final c = contract;
    // 서버 기록은 UTC 절대 시각 — 표기는 센터(KST) 벽시계. 일시는 분 단위까지
    // 보여야 "언제 서명했나"에 답이 된다(체결 증적의 첫 행).
    final signedKst = c.signedAt == null ? null : DateFmt.toKst(c.signedAt!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('체결 정보',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          if (signedKst != null)
            _InfoRow('서명 일시', '${DateFmt.isoDate(signedKst)} ${DateFmt.hhmm(signedKst)}'),
          // 본인인증 수단 — 서명 이미지가 있는 계약만: 이미지 존재가 P44 이후 앱
          // 서명 경로(휴대폰 본인인증 세션 필수)로 체결됐음을 데이터로 증명한다.
          // 그 전 계약도 사실상 같은 경로지만, 데이터가 말하지 않는 것을 행으로
          // 만들지 않는다(지어내지 않기).
          if (c.hasSignatureImage) const _InfoRow('본인인증 수단', '휴대폰 본인인증 계정'),
          if (c.signerIp != null) _InfoRow('서명 IP', c.signerIp!),
          if (c.sha256 != null) _InfoRow('문서 해시', _hash12(c.sha256!), mono: true),
          if (c.signatureSha256.isNotEmpty)
            _InfoRow('서명 이미지 해시', _hash12(c.signatureSha256), mono: true),
          if (c.templateVersion.isNotEmpty) _InfoRow('계약서 버전', c.templateVersion),
          if (c.firstSentAt != null)
            _InfoRow('최초 발송일', DateFmt.isoDate(DateFmt.toKst(c.firstSentAt!))),
          const SizedBox(height: 6),
          // 정직 캡션(결정 7) — 여기서 한 글자라도 더 나가면(예: "법적 효력이
          // 추정됩니다") 없는 법을 지어내는 문구가 된다.
          const Text(
            '체결 사실의 입증 자료입니다',
            style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 체결 정보 한 행 — [_Row]와 같은 골격, 해시 값만 고정폭 폰트([mono])를 쓴다
/// (자릿수 대조가 목적인 값이라서 — 서식 블록의 폰트 폴백 규약과 동일).
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: mono
                  // 안드로이드는 'monospace'가 시스템 모노로 매핑되고, iOS는 그
                  // 이름이 없어 폴백(Menlo)으로 떨어진다(contract_document_view의
                  // 서식 블록과 같은 선택).
                  ? const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['Menlo', 'Courier New'],
                    )
                  : const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// 본문 대신 서는 한 줄 안내(미지 버전·표시 불가) — PDF 안내 줄과 같은 차분한 톤.
/// 열람 불가는 오류가 아니라 사실이고, 요약 메타는 위에 전부 있다.
class _BodyNotice extends StatelessWidget {
  const _BodyNotice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.line.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
