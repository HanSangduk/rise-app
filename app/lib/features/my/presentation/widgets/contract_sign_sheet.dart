import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/my/domain/ledger_summary.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/contract_body.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_document_view.dart';
import 'package:rise_member/features/my/presentation/widgets/signature_pad.dart';
import 'package:url_launcher/url_launcher.dart';

/// 계약 서명 시트 — status=sent 계약의 요약(상품·금액·발송일)을 보여주고
/// 동의 체크 후 자체서명한다(POST /v1/contracts/{id}/sign, v1.4 P27).
/// 예약 확정·일시정지 시트와 같은 패턴: 제출 중 표시·이중 탭 방지·에러 인라인.
///
/// P39(§D ⑤): 문서 스냅샷(template_version+vars, v2.18)이 있으면 요약 **위에**
/// 계약서 전문을 스크롤 영역으로 올리고, 동의 체크박스는 끝까지 스크롤한 뒤에만
/// 활성화한다. 스냅샷이 없으면(발행 래치 OFF 동안의 전부·레거시) 이 화면은 오늘의
/// 요약 고지 그대로다 — P28이 적법화한 기준선이라 아래 요약·정산·약관 고지는
/// 전문이 떠도 전부 그대로 남는다(전문은 요약을 대체하지 않고 위에 얹힌다).
///
/// P44(결정 5): 시트가 2단이 됐다. 1단은 위 문단 그대로(스크롤 게이트·요약 고지·
/// 동의 체크)고 버튼만 "서명하기 = 2단 진입"이다. 2단은 문서가 확인 한 줄로 접히고
/// 자필 서명 패드가 선다 — 최종 버튼 "동의하고 서명합니다"(모두싸인 계열 표준 문구)는
/// 패드에 실제 표식이 있어야 열린다. 전문 없는 경로(레거시·미지 버전·표시 불가)도
/// **같은 2단 패드**를 탄다: 서명 이미지는 전문 열람 가능 여부와 무관하게 서명
/// 행위 자체의 증거다(결정 1 — 효력의 뿌리는 인증 계정+동의 행위).
///
/// [onViewSigned]: 체결 완료 단계의 [계약서 보기] — 시트가 닫힌 **뒤** 재조회
/// 반영본(서명 이미지·체결 정보 포함)으로 호출된다. 상세 시트를 여는 쪽이 호출자인
/// 이유: 이 시트의 context는 pop과 함께 죽으므로, 살아남는 화면(my_screen)의
/// context로 여는 것이 onSignTap/onDetailTap과 같은 배선 방향이다.
Future<void> showContractSignSheet(
  BuildContext context, {
  required ContractItem contract,
  void Function(ContractItem contract)? onViewSigned,
}) {
  final submitting = ValueNotifier(false);
  return showRiseSheet<void>(
    context,
    // P44 결정 5 "enableDrag 끔" — 2단 서명 패드 위에서 시작한 세로 획이 시트
    // 드래그-닫기와 제스처 아레나에서 경합해 시트가 내려가 버리는 문제의 차단
    // (signature_pad JS 라이브러리 계열의 알려진 함정, P44 리서치). 라우트
    // 파라미터는 생성 시점에 고정이라 단계별 토글은 불가능하다 — 시트 전체에서
    // 꺼서 상태 전환에 안전하게 만든다. 스크림 탭·뒤로가기 닫힘은 그대로다.
    enableDrag: false,
    // 제출 중 잠금 신호(P56 M1) — 드래그는 이미 꺼져 있지만 스크림 탭·시스템 백은 열려
    // 있다. 서명 PNG를 실은 요청이 날아가는 동안 닫히면 "서명됐나?"를 알 길이 없고,
    // 다시 열어 서명하면 서버 sent→signed 가드의 400을 본다(rise_sheet.dart 헤더).
    submitting: submitting,
    builder: (_) => _ContractSignSheet(
      contract: contract,
      onViewSigned: onViewSigned,
      submitting: submitting,
    ),
  );
}

/// 시트 단계(P44 결정 5) — 1단 확인 → 2단 서명 → 체결 완료.
enum _SignStage { review, sign, done }

class _ContractSignSheet extends ConsumerStatefulWidget {
  const _ContractSignSheet({
    required this.contract,
    required this.submitting,
    this.onViewSigned,
  });
  final ContractItem contract;
  final void Function(ContractItem contract)? onViewSigned;

  /// 제출 중 신호 — 래퍼의 잠금과 같은 객체.
  final ValueNotifier<bool> submitting;

  @override
  ConsumerState<_ContractSignSheet> createState() => _ContractSignSheetState();
}

class _ContractSignSheetState extends ConsumerState<_ContractSignSheet> {
  bool _agreed = false;

  /// 저장소는 [widget.submitting] 하나다(rise_sheet.dart `submitting` 절).
  bool get _submitting => widget.submitting.value;
  String? _error;

  _SignStage _stage = _SignStage.review;

  /// 서명 패드 상태 — 시트가 쥔다: 2단↔1단을 오가도(다시 보기) 획이 보존된다.
  final _pad = SignaturePadController();

  /// 내보낸 서명 PNG — 체결 완료 단계의 썸네일. 서버 재조회가 아니라 로컬 바이트라
  /// 네트워크와 무관하게 뜬다(내보내기 실패면 null — 썸네일 없이 문구만).
  Uint8List? _signaturePngBytes;

  /// [계약서 보기] 진행 중 — 재조회 대기 동안 이중 탭 방지.
  bool _openingDetail = false;

  // ── 계약서 전문(P39 시트 슬라이스, §D ⑤) ──────────────────────────────

  /// 전문 표시 판정. 스냅샷 없는 계약은 initState에서 곧장 None — 레거시는 첫
  /// 프레임부터 오늘 화면 그대로다(로딩 상태를 스치지도 않는다).
  ContractBodyState _body = const ContractBodyLoading();
  bool _bodyResolveStarted = false;

  /// 전문 스크롤 — "끝까지 읽음" 판정을 위해 시트가 컨트롤러를 직접 쥔다
  /// (contract_document_view가 스크롤을 호출자 몫으로 남긴 이유가 이 게이트다).
  final _docScroll = ScrollController();

  /// 끝까지 읽음 래치 — 한 번 열리면 닫히지 않는다. 읽고 나서 위로 되감아도
  /// "끝까지 본 사실"은 사라지지 않는다. 2단을 다녀와도 마찬가지다(시트 상태라
  /// 단계 전환이 지우지 못한다 — 지워지면 동의가 풀리는 역행이다).
  bool _readToEnd = false;

  /// maxScrollExtent 도달 판정의 여유(px) — 물리 픽셀 반올림·드래그 정지 잔여 흡수.
  static const _readEpsilon = 8.0;

  @override
  void initState() {
    super.initState();
    _docScroll.addListener(_recheckReadToEnd);
    // 패드 획 변화 → 최종 버튼 활성 재평가.
    _pad.addListener(_onPadChanged);
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
    // DefaultAssetBundle 경유 — 운영은 rootBundle 폴백이고, 테스트는 가짜 번들로
    // 짧은/깨진 템플릿을 주입한다(didChangeDependencies인 이유: initState에서는
    // 상속 위젯 조회가 안전하지 않다).
    resolveContractBody(bundle: DefaultAssetBundle.of(context), contract: widget.contract)
        .then((resolved) {
      if (!mounted) return;
      setState(() => _body = resolved);
      if (resolved is ContractBodyReady) {
        // 문서가 뷰포트보다 짧으면 스크롤 이벤트가 영영 없다 — 첫 레이아웃이 끝난
        // 직후 한 번 판정해 "짧은 문서 = 이미 끝까지 봄"으로 연다.
        WidgetsBinding.instance.addPostFrameCallback((_) => _recheckReadToEnd());
      }
    });
  }

  @override
  void dispose() {
    _docScroll.dispose();
    _pad.removeListener(_onPadChanged);
    _pad.dispose();
    widget.submitting.dispose();
    super.dispose();
  }

  void _onPadChanged() {
    if (mounted) setState(() {});
  }

  /// "끝까지" = maxScrollExtent 도달(남은 거리 extentAfter ≤ ε). 문서가 뷰포트보다
  /// 짧으면 maxScrollExtent가 0이라 첫 판정에서 바로 열린다.
  void _recheckReadToEnd() {
    if (_readToEnd || !_docScroll.hasClients) return;
    if (_docScroll.position.extentAfter <= _readEpsilon) {
      setState(() => _readToEnd = true);
    }
  }

  /// 동의 게이트 — 전문이 떴으면 끝까지 읽어야 열린다(§D ⑤). 전문이 없거나 표시
  /// 불가일 때는 닫지 않는다: 그때의 동의 대상은 오늘의 요약 고지(P28 적법 기준선)
  /// 그대로이고, 전문 열람 불가가 서명 자체를 막아서는 안 된다(§D ④).
  bool get _consentGateOpen => switch (_body) {
        ContractBodyReady() => _readToEnd,
        // 한 프레임 남짓 — 열어 뒀다가 문서 도착과 함께 닫으면 이미 체크한 동의가
        // 풀리는 역행이 생기므로, 판정 전에는 닫아 둔다.
        ContractBodyLoading() => false,
        ContractBodyNone() ||
        ContractBodyNeedsAppUpdate() ||
        ContractBodyUnavailable() =>
          true,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (_stage) {
          _SignStage.review => _reviewChildren(context),
          _SignStage.sign => _signChildren(context),
          _SignStage.done => _doneChildren(context),
        },
      ),
    );
  }

  /// 1단 — 오늘의 화면 그대로(P28 요약 고지 + P39 전문 게이트). 버튼만 다르다:
  /// 활성 조건은 종전과 같고(동의 체크), 탭의 의미가 "제출"에서 "서명 단계 진입"으로
  /// 바뀌었다(P44 결정 5). 제출은 2단의 "동의하고 서명합니다"가 한다.
  List<Widget> _reviewChildren(BuildContext context) {
    final c = widget.contract;
    // 조회 실패해도 화면은 죽지 않는다 — 다만 폴백(24h/10%)을 **사실처럼 찍지 않는다**
    // (P56 H3). 이 박스 바로 아래서 "위 계약 내용을 확인했으며 동의합니다"를 받는다:
    // 센터 실제 마감이 48시간인데 "24시간 전까지 무료"에 동의한 회원은 30시간 전 취소로
    // 차감되고, 그 문구를 근거로 다툰다. `isFallback`의 dartdoc이 적은 그 사고다.
    final policy = ref.watch(centerPolicyProvider).value ?? CenterPolicy.fallback;
    // 위약금율은 계약 스냅샷(v1.5) 우선, 없으면(레거시) 현재 정책 — 서버 refundBasis와
    // 같은 순서. 스냅샷도 없고 정책도 폴백이면 **모르는 것**이라 숫자를 지어내지 않는다.
    final rateKnown = c.penaltyRate != null || !policy.isFallback;
    final rate = c.penaltyRate ?? policy.penaltyRate;
    final rateLabel = rateKnown ? _penaltyLabel(rate) : '확인하지 못했어요';
    return [
      const Text('계약 서명', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text(
        '내용을 확인하고 서명하면 계약이 체결돼요 (서명 시각은 서버에 기록)',
        style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 12),
      // 계약서 전문(§D ⑤) — 요약 위에 얹힌다. 스냅샷 없으면 빈 목록이라 오늘
      // 화면과 위젯 하나까지 같다.
      ..._documentSection(context),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line, width: 1.5),
          // 원래 12 — 목업 근거 없는 일회성이라 card(14)로 흡수했다(H3, 2px 변화).
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          children: [
            _SummaryRow('상품', c.product),
            // "결제 금액"이 아니라 **계약가**다 — 분할로 내는 중이면 지금까지 낸 돈과
            // 다르고, 회차 단가·위약금은 이 값에서 나온다(어드민 v1.5 어휘와 통일).
            _SummaryRow('계약가', MoneyFormat.won(c.paidAmount)),
            // 위약금율은 **동의를 받기 전에 반드시 보여야 한다**. 종전엔 상품·금액·
            // 발송일 세 줄만 띄우고 "위 계약 내용을 확인했으며 동의합니다"를 받았다 —
            // 회원이 본 적 없는 조건에 동의시킨 셈이고, 방문판매법 제30조②(계약서
            // 교부)의 필수 기재사항이 빠진 상태다.
            //
            // 계약에 스냅샷이 있으면 그 값, 없으면(v1.5 이전 레거시) 현재 센터 정책 —
            // 서버 refundBasis가 정확히 그 순서로 고른다. 여기서 다른 값을 그리면
            // "계약서 30% / 실제 공제 10%"로 갈렸던 사고(policy.go Validate 주석)의
            // 재현이 된다.
            _SummaryRow('중도 해지 위약금', rateLabel),
            // P44 마감 리뷰: KST 통일 — 상세 시트·문서 체결일과 같은 시간축.
            _SummaryRow('발송일', c.sentAt == null ? '-' : DateFmt.isoDate(DateFmt.toKst(c.sentAt!))),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.line.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '해지하면 이렇게 정산돼요',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            // 서버 RefundQuote와 같은 순서·같은 말. 문구가 계산과 갈리면
            // 회원은 환불액을 받고 나서야 조건을 알게 된다.
            Text(
              // 기준액을 반드시 밝힌다. "위약금 10%"만 쓰면 회원은 **자기가 낸 돈의 10%**로
              // 읽는데, 실제 기준은 계약가다(공정위 고시 제2019-9호 제2조2호 "총계약대금 =
              // 지급하기로 한 금액" + 별표 "헬스·피트니스업 총계약대금의 10%"). 분할로 내는
              // 중이면 두 값이 갈리고, 그때 회원이 처음 알게 되는 건 정산서에서다.
              //
              // 반대로 빼기 시작하는 돈은 **실제 낸 금액**이다(같은 고시 제5조① "사업자에게
              // 지급한 계약대금에서"). 같은 고시가 두 자리에 다른 단어를 쓴다.
              '환불액 = 지금까지 낸 금액 − 사용한 회차 금액 − 위약금\n'
              '· 회차 단가 = 계약가 ${MoneyFormat.won(c.paidAmount)} ÷ 총 회차\n'
              '${rateKnown ? '· 위약금 = 계약가의 ${_penaltyLabel(rate)} (낸 금액이 아니라 계약가 기준이에요)' : '· 위약금율은 센터 정책을 확인하지 못했어요 — 계약서 본문의 기준을 따라요'}\n'
              // 모르면 시간을 말하지 않는다 — 폴백 24시간은 이 센터의 기준이 아니라 앱의 기본값이다.
              '${policy.isFallback ? '· 예약 취소 기준(무료 취소 마감)은 센터 정책을 확인하지 못했어요 — 계약서 본문의 기준을 따라요' : '· 예약은 수업 ${policy.cancelCutoffHours}시간 전까지 무료로 취소할 수 있어요'}',
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      // 전문이 뜬 경우 끝까지 읽기 전에는 체크가 잠긴다(§D ⑤). 잠긴 이유는 위
      // _documentSection의 안내 한 줄이 말한다 — 이유 없는 회색 체크박스를 두지
      // 않는다.
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        value: _agreed,
        activeColor: AppColors.brand,
        title: const Text(
          '위 계약 내용과 이용약관을 확인했으며 동의합니다',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        onChanged: (_submitting || !_consentGateOpen)
            ? null
            : (v) => setState(() => _agreed = v ?? false),
      ),
      // 전문은 웹으로 — 앱에 박으면 개정할 때마다 스토어 심사를 다시 통과해야 한다
      // (P26 LegalLinksCard와 같은 이유).
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openTerms,
        child: const Padding(
          padding: EdgeInsets.only(left: 4, top: 12, bottom: 12),
          child: Text(
            '이용약관 전문 보기',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.brand,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
      RiseButton(
        label: '서명하기',
        expand: true,
        onPressed: _agreed ? () => setState(() => _stage = _SignStage.sign) : null,
      ),
    ];
  }

  /// 2단 — 문서는 확인 한 줄로 접히고(높이 경합 해소, P44 결정 5) 패드가 선다.
  /// 여기 오는 모든 경로(전문·레거시·미지 버전·표시 불가)가 같은 패드를 쓴다.
  List<Widget> _signChildren(BuildContext context) {
    return [
      const Text('계약 서명', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      // 접힌 문서의 확인 라인 — [다시 보기]는 1단 복귀. 동의 체크·끝까지 읽음 래치는
      // 시트 상태라 그대로 보존된다(돌아갔다 와도 다시 읽기를 강요하지 않는다).
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _submitting ? null : () => setState(() => _stage = _SignStage.review),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  '계약 내용을 확인했습니다',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '다시 보기',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      // 전자 교부 고지(P44 결정 8 연장) — 계약서 제18조·제23조가 이미 약속한 교부
      // 방식·재열람 경로를 서명 **직전에** 한 줄로 다시 말한다. 전자문서 교부 시
      // 열람 가능 상태를 소비자에게 알리도록 하는 입법 패턴(방판법 §7④ 계열)을 참조.
      const _DocumentNotice(
        '이 계약은 전자문서로 체결·교부되며, 마이 > 계약에서 언제든 다시 열람할 수 있어요',
      ),
      const SizedBox(height: 10),
      SignaturePad(controller: _pad),
      const SizedBox(height: 8),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!, style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
        ),
      RiseButton(
        // 모두싸인 계열 표준 문구(P44 결정 5) — 1단의 체크 동의와 지금의 자필 표식이
        // 하나의 서명 행위임을 버튼이 말한다.
        label: _submitting ? '서명 중…' : '동의하고 서명합니다',
        expand: true,
        onPressed: (_pad.isValid && !_submitting) ? _submit : null,
      ),
    ];
  }

  /// 체결 완료 — 시트를 곧장 닫지 않고 체결 사실·방금 그린 서명·재열람 경로를
  /// 그 자리에서 확인시킨다. 목록 재동기화는 signContract 성공이 이미 걸었다.
  List<Widget> _doneChildren(BuildContext context) {
    return [
      const Text('계약이 체결되었습니다', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text(
        '서명 시각과 서명 이미지가 계약에 기록됐어요 — 마이 > 계약에서 언제든 다시 열람할 수 있어요',
        style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 12),
      if (_signaturePngBytes != null) ...[
        Container(
          height: 88,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          // 방금 내보낸 로컬 바이트 그대로 — 서버 왕복 없이 뜨고, 서버에 저장된 것과
          // 같은 이미지다(같은 바이트를 base64로 보냈다).
          child: Image.memory(_signaturePngBytes!, fit: BoxFit.contain),
        ),
        const SizedBox(height: 12),
      ],
      if (widget.onViewSigned != null) ...[
        RiseButton(
          label: '계약서 보기',
          expand: true,
          onPressed: _openingDetail ? null : _openSignedDetail,
        ),
        const SizedBox(height: 8),
        RiseButton(
          label: '닫기',
          style: RiseButtonStyleKind.outline,
          expand: true,
          onPressed: _openingDetail ? null : () => Navigator.of(context).pop(),
        ),
      ] else
        // 콜백 없는 호출자(배선이 침습적인 자리) — 재동기화는 이미 끝났으니 닫기만.
        RiseButton(
          label: '닫기',
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
    ];
  }

  /// 전문 영역(§D ⑤) — 판정 갈래별로 요약 위에 얹을 위젯들. 스냅샷 없음(오늘의
  /// 전부)·로딩 한 프레임은 빈 목록이라 기존 화면이 그대로다.
  List<Widget> _documentSection(BuildContext context) {
    switch (_body) {
      case ContractBodyNone() || ContractBodyLoading():
        return const [];

      case ContractBodyReady(:final document):
        return [
          // Flexible: 요약·정산·버튼(법정 고지와 행동 수단)을 먼저 앉히고 남는
          // 높이만 전문이 쓴다 — 작은 화면에서 전문이 서명 버튼을 밀어내지 않는다.
          // 화면 45% 상한은 시트가 상단(노치)까지 붙지 않게 한 번 더 누르는 것.
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  controller: _docScroll,
                  padding: const EdgeInsets.all(12),
                  child: ContractDocumentView(document: document),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 체크박스가 왜 잠겨 있는지를 말한다 — 끝까지 읽으면 이 줄은 사라진다.
          if (!_readToEnd)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '전문을 끝까지 읽으면 동의할 수 있어요',
                style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4),
              ),
            ),
        ];

      case ContractBodyNeedsAppUpdate():
        // 미지 버전 — 렌더하지 않는다(§D ④ :916-917). 차분한 안내 한 장뿐,
        // 아래 요약 고지·서명은 그대로 진행된다.
        return const [
          _DocumentNotice('새 계약서 양식입니다 — 앱을 업데이트하면 전문을 열람할 수 있어요'),
          SizedBox(height: 8),
        ];

      case ContractBodyUnavailable():
        // 전문을 그릴 수 없는 스냅샷(렌더 거부·자산 결손) — 사실대로 말하고 요약
        // 경로로 진행한다. 가짜 문서도, 조용한 숨김도 없다(P33 정직 규약).
        return const [
          _DocumentNotice('계약서 전문을 표시할 수 없어요 — 아래 요약 내용을 확인한 뒤 서명할 수 있어요'),
          SizedBox(height: 8),
        ];
    }
  }

  /// 소수 자리를 억지로 붙이지 않는다 — "10%"를 "10.0%"로 쓰면 정밀해 보일 뿐이다.
  String _penaltyLabel(double rate) {
    final pct = rate * 100;
    return '${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%';
  }

  Future<void> _openTerms() async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(LegalLinks.terms), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        riseSnackBar('브라우저를 열지 못했어요 — 주소: ${LegalLinks.terms}', kind: RiseSnackKind.danger),
      );
    }
  }

  Future<void> _submit() async {
    // P44 마감 리뷰 L: 재진입 가드 — 이중 탭 방지가 버튼 리빌드(1프레임 창)에만 의존했다.
    // 서버 sent→signed 가드가 2번째를 400으로 막긴 하지만, 회원에게 에러를 보일 이유가 없다.
    if (_submitting) return;
    setState(() {
      widget.submitting.value = true;
      _error = null;
    });
    // 서명 이미지 내보내기(P44 결정 2) — 실패해도 서명 자체는 막지 않는다:
    // 바디 없는 sign이 계속 유효하고(결정 6), 효력의 뿌리는 인증 계정+동의
    // 행위다(결정 1). PNG 인코딩 한 번의 실패로 적법한 서명을 좌초시키지 않는다.
    String? signaturePng;
    try {
      final bytes = await _pad.toPngBytes(
        devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
      );
      _signaturePngBytes = bytes;
      signaturePng = base64Encode(bytes);
    } catch (_) {
      _signaturePngBytes = null;
      signaturePng = null;
    }
    if (!mounted) return;
    final result = await ref
        .read(myViewModelProvider.notifier)
        .signContract(widget.contract.id, signaturePng: signaturePng);
    if (!mounted) return;
    switch (result) {
      case Ok():
        // 시트를 닫는 대신 체결 완료 단계로(P44) — 서명 직후 회원이 확인하고 싶은
        // 것(체결 사실·자기 서명·재열람 경로)을 그 자리에서 보여준다. 종전의
        // "서명 완료" 스낵바는 이 단계가 대체한다.
        setState(() {
          widget.submitting.value = false;
          _stage = _SignStage.done;
        });
      case Err(:final failure):
        // 4xx 거부(RejectedFailure)는 이미 서명됨/무효화 등 서버와 목록이 어긋난
        // 경우가 대부분 — 목록을 재동기화해 낡은 '서명 대기' 행이 반복 에러를
        // 만들지 않게 한다(네트워크 실패는 목록이 낡은 게 아니므로 제외).
        if (failure is RejectedFailure) {
          ref.read(myViewModelProvider.notifier).refresh();
        }
        setState(() {
          widget.submitting.value = false;
          _error = failure.message;
        });
    }
  }

  /// [계약서 보기] — signContract 성공이 걸어 둔 재조회의 완료를 기다려 서명
  /// 반영본(서명 이미지·체결 정보)을 찾고, 시트를 닫은 뒤 호출자 콜백으로 상세를
  /// 연다. 재조회가 실패하면 손에 있는 값으로 연다 — 지어내지 않고, 열람 자체를
  /// 막지도 않는다.
  Future<void> _openSignedDetail() async {
    final onViewSigned = widget.onViewSigned;
    if (onViewSigned == null) return;
    setState(() => _openingDetail = true);
    var updated = widget.contract;
    try {
      final summary = await ref.read(myViewModelProvider.future);
      updated = summary.contracts.firstWhere(
        (c) => c.id == widget.contract.id,
        orElse: () => widget.contract,
      );
    } catch (_) {
      // 재조회 실패 — 폴백은 위 주석 그대로.
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    onViewSigned(updated);
  }
}

/// 전문 대신 서는 한 줄 안내(미지 버전·표시 불가·전자 교부 고지) — 정산 박스와 같은
/// 차분한 톤. 경고색을 쓰지 않는 이유: 요약 고지 서명은 오늘의 정상 경로(P28)지
/// 오류가 아니다.
class _DocumentNotice extends StatelessWidget {
  const _DocumentNotice(this.message);
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
