import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/camera_permission_view.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/records/data/inbody_sheet_reader.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/inbody_sheet_parser.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

/// 인바디 입력 시트 — 회원이 결과지를 보고 숫자 6개를 옮겨 적거나, **결과지
/// 사진에서 읽어 미리 채운다**(P20, 온디바이스 OCR — 자동 저장 없음: 프리필 후
/// 사람이 확인·수정하고 저장한다. 사진은 기기 안에서 숫자만 뽑고 버린다).
///
/// 인식 성공/부분/0건/실패는 전부 **이 같은 폼**으로 떨어진다 — 별도 에러 화면이
/// 없다. 수기 입력이 곧 실패 경로다.
///
/// 라우트가 아니라 시트다(`core/router/app_router.dart` 규약, 앱 내 6곳 선례).
/// 구조는 `features/my/presentation/widgets/hold_request_sheet.dart`를 그대로
/// 따른다: 키보드 인셋 패딩 · `_submitting` 잠금 · 사전 판정 버튼 잠금 · 제출
/// 직전 이중 방어 · 성공 시 pop+스낵바 · 실패 시 시트 유지+인라인 에러.
Future<void> showInbodyAddSheet(BuildContext context) {
  // 제출 중 잠금 신호(P56 M1) — 이 시트가 그 결함의 대표 사례였다: 6칸을 채우고 저장 →
  // 드래그 → 서버 400 → **입력도 사라지고 아무 말도 없다**(rise_sheet.dart 헤더).
  final submitting = ValueNotifier(false);
  return showRiseSheet<void>(
    context,
    submitting: submitting,
    builder: (_) => _InbodyAddSheet(submitting: submitting),
  );
}

class _InbodyAddSheet extends ConsumerStatefulWidget {
  const _InbodyAddSheet({required this.submitting});

  /// 제출 중 신호 — 래퍼의 잠금과 같은 객체.
  final ValueNotifier<bool> submitting;

  @override
  ConsumerState<_InbodyAddSheet> createState() => _InbodyAddSheetState();
}

class _InbodyAddSheetState extends ConsumerState<_InbodyAddSheet> {
  /// 측정일 — 기본값은 센터(KST) 오늘. 기기 로컬 날짜로 잡으면 해외 체류 시
  /// 서버가 보는 "오늘"과 하루 어긋난다(DateFmt 시간축 규약).
  DateTime _date = DateFmt.todayKst();

  final _controllers = {for (final m in InbodyMetric.values) m: TextEditingController()};

  /// 칸별 포커스 — errorText가 "지금 만지는 칸인지"에 달려 있어 직접 소유한다.
  final _focusNodes = {for (final m in InbodyMetric.values) m: FocusNode()};

  /// 저장소는 [widget.submitting] 하나다(rise_sheet.dart `submitting` 절).
  bool get _submitting => widget.submitting.value;

  /// 서버가 돌려준 거부/실패 문구. 사전 판정과 구분해 둔다 — 입력을 고치면
  /// 사라져야 하는 값이라 값·날짜가 바뀔 때 지운다.
  String? _error;

  /// 사진 인식이 돌아가는 동안 버튼을 잠근다(중복 픽커 방지). 폼은 그대로 둔다 —
  /// 읽는 동안에도 수기 입력을 막을 이유가 없다.
  bool _reading = false;

  /// 사진 읽기 결과 안내(몇 칸 채웠는지 / 못 읽었는지). 서버 에러(_error)와
  /// 별개다 — 저장 시도와 무관하게 사진 버튼 아래에 붙는다.
  String? _readNote;

  /// 사진에서 읽어 온 뒤 아직 회원이 손대지 않은 칸 — 칸 끝에 "사진" 표식을
  /// 붙여 어느 값이 기계가 읽은 것인지 보이게 한다. 회원이 고치는 순간 그 칸은
  /// 회원의 입력이다(표식 제거).
  final Set<InbodyMetric> _prefilled = {};

  /// 사진에서 채우기를 보여줄지 — **Android 전용**(P20).
  ///
  /// iOS를 막는 이유: google_mlkit_text_recognition의 podspec이 iOS 15.5를
  /// 요구하는데 프로젝트 배포 타깃은 15.0이고 Podfile도 아직 없다 — iOS 빌드
  /// 정비는 이번 범위 밖이라(P20), 눌러도 동작을 보증할 수 없는 버튼을 그리지
  /// 않는다(과장 금지 규약). 시트 상단 안내문도 이 값에 맞춰 갈린다 — iOS에는
  /// "아직 없어요"가 계속 사실이다.
  bool get _photoFillAvailable => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    for (final node in _focusNodes.values) {
      node.addListener(_onFocusChanged);
    }
  }

  /// 포커스 이동 때 다시 그린다 — 떠난 칸의 에러가 그 순간 나타나야 한다.
  /// (시트 pop 도중에도 노드가 포커스를 잃으며 부르므로 mounted 가드.)
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final node in _focusNodes.values) {
      node
        ..removeListener(_onFocusChanged)
        ..dispose();
    }
    widget.submitting.dispose();
    super.dispose();
  }

  Map<InbodyMetric, String> get _raw => {for (final e in _controllers.entries) e.key: e.value.text};

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider);

    // 동의 사전 분기. 서버 `CreateInbody`가 sensitive 동의 없는 저장을 거부하므로
    // (P8), 6칸을 다 채운 뒤에 거부당하게 두지 않는다.
    //
    // **조회 실패는 막지 않는다** — 최종 판정은 서버가 한다. 프로필 조회가
    // 흔들릴 때 이미 동의한 회원의 저장까지 막으면, 앱이 서버보다 엄격해져
    // 회원에겐 아무 방법이 없는 막다른 길이 된다(camera_view_model 규약).
    return switch (profile) {
      AsyncLoading() => const _SheetShell(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
        ),
      ),
      AsyncData(:final value) when value.consent?.sensitive != true => const _ConsentRequiredBody(),
      _ => _form(context),
    };
  }

  Widget _form(BuildContext context) {
    final raw = _raw;
    final blocked = InbodyInputRules.hasBlockingError(raw);
    // 조합 오류는 어느 한 칸의 잘못이 아니라 세 칸의 관계라 errorText로 붙일 자리가
    // 없다 — 버튼 위 한 줄로 말한다. 살아 있는 문구는 하나만: 사전 판정이 있으면
    // 그게 지금의 진실이고, 없을 때만 직전 서버 응답을 남긴다(hold_request_sheet).
    final crossError = InbodyInputRules.crossFieldError(raw);
    final blockingMessage = crossError ?? _error;
    final warning = InbodyInputRules.consistencyWarning(
      weightRaw: raw[InbodyMetric.weight] ?? '',
      bfmRaw: raw[InbodyMetric.bfm] ?? '',
      pbfRaw: raw[InbodyMetric.pbf] ?? '',
    );

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('인바디 기록 추가', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            // 무엇을 하는 화면인지 정확히 말한다. 사진 기능이 없는 플랫폼(iOS,
            // _photoFillAvailable 주석)에서는 "아직 없어요"가 계속 사실이므로
            // 문구를 갈지 않는다 — 있는 곳에서만 있다고 말한다.
            _photoFillAvailable
                ? '결과지에 인쇄된 숫자 6개를 그대로 옮겨 적어주세요\n'
                      '아래 버튼으로 결과지 사진에서 읽어와 채울 수도 있어요'
                : '결과지에 인쇄된 숫자 6개를 그대로 옮겨 적어주세요\n'
                      '사진으로 자동 입력하는 기능은 아직 없어요',
            style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (_photoFillAvailable) ...[
            RiseButton(
              label: _reading ? '사진에서 읽는 중…' : '사진에서 채우기',
              style: RiseButtonStyleKind.outline,
              expand: true,
              onPressed: (_submitting || _reading) ? null : _startPhotoFill,
            ),
            if (_readNote case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  note,
                  style: const TextStyle(fontSize: 11, color: AppColors.warn, height: 1.5),
                ),
              ),
            const SizedBox(height: 10),
          ],
          _DateField(value: _date, onTap: _submitting ? null : _pickDate),
          const SizedBox(height: 10),
          for (var i = 0; i < InbodyMetric.values.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _numberField(InbodyMetric.values[i])),
                  const SizedBox(width: 8),
                  Expanded(child: _numberField(InbodyMetric.values[i + 1])),
                ],
              ),
            ),
          // 경고(비차단)는 막는 문구가 없을 때만 — 붉은 줄과 노란 줄이 같이 뜨면
          // 무엇을 먼저 고쳐야 하는지 알 수 없다.
          if (warning != null && blockingMessage == null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                warning,
                style: const TextStyle(fontSize: 11, color: AppColors.warn, height: 1.5),
              ),
            ),
          if (blockingMessage case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                message,
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger, height: 1.5),
              ),
            ),
          const SizedBox(height: 8),
          RiseButton(
            label: _submitting ? '저장 중…' : '저장하기',
            expand: true,
            // 서버가 확실히 거부할 값이면 왕복하지 않는다. 다만 **빈 칸은 잠그지
            // 않는다** — 미입력은 거부가 아니라 미완성이라, 눌러서 무엇이 빠졌는지
            // 안내를 받게 둔다(hold_request_sheet과 같은 원칙).
            onPressed: (_submitting || blocked) ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _numberField(InbodyMetric metric) {
    final focusNode = _focusNodes[metric]!;
    return TextField(
      controller: _controllers[metric],
      focusNode: focusNode,
      enabled: !_submitting,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [_decimalOnePlace],
      decoration: InputDecoration(
        // 라벨은 어드민 `BodyPhotos.tsx`의 NumField와 문자 그대로 같다 — 회원이
        // 옮겨 적은 칸과 코치가 보는 칸이 같은 이름이어야 한다. 약어만으로는
        // 회원이 무슨 값인지 모르므로 한글 뜻을 헬퍼에 함께 둔다.
        labelText: metric.formLabel,
        helperText: _helperFor(metric),
        helperMaxLines: 3,
        // **지금 만지는 칸은 판정하지 않는다** — "7"(체중 70의 첫 타), "14"(BMR
        // 1420의 도중)처럼 정상 값을 입력하는 과정이 전부 범위 밖이라, 키 입력마다
        // 판정하면 옮겨 적는 내내 붉은 에러가 명멸한다. 포커스가 떠난 칸만
        // 판정한다(값은 타이핑으로만 들어오므로 "안 만진 칸"은 비어 있고, 빈 칸은
        // fieldError가 null이다). 버튼 잠금([InbodyInputRules.hasBlockingError])은
        // 종전대로 실시간 — 판정을 미루는 건 표시뿐이다. 제출 시도 시점의 표시는
        // 따로 필요 없다: 범위 에러가 있으면 버튼이 이미 잠겨 제출 자체가 안 된다.
        errorText: focusNode.hasFocus
            ? null
            : InbodyInputRules.fieldError(metric, _controllers[metric]!.text),
        errorMaxLines: 3,
        // 사진에서 읽어 온 값 표식 — 어느 칸이 기계가 채운 것인지 보이게.
        // 회원이 그 칸을 고치면 이제 회원의 입력이므로 표식을 뗀다(onChanged).
        suffixText: _prefilled.contains(metric) ? '사진' : null,
        suffixStyle: const TextStyle(fontSize: 10, color: AppColors.warn),
      ),
      onChanged: (_) => setState(() {
        _error = null;
        _prefilled.remove(metric);
      }),
    );
  }

  // ── 사진에서 채우기(P20) ─────────────────────────────────────────────

  /// 버튼 → 갤러리/카메라 선택 → 인식 → 프리필. 어떤 결과든 이 폼으로 돌아온다.
  Future<void> _startPhotoFill() async {
    final source = await _pickPhotoSource();
    if (source == null || !mounted) return;
    if (source == InbodyPhotoSource.camera) {
      final granted = await _ensureCameraPermission();
      if (!granted || !mounted) return;
    }
    setState(() {
      _reading = true;
      _readNote = null;
    });
    final outcome = await ref.read(inbodySheetReaderProvider).read(source);
    if (!mounted) return;
    setState(() {
      _reading = false;
      switch (outcome) {
        case InbodySheetReadCancelled():
          break; // 회원이 스스로 물렸다 — 아무 말도 하지 않는다.
        case InbodySheetReadFailed():
          _readNote = '사진에서 값을 읽지 못했어요 — 결과지를 다시 찍거나 직접 입력해주세요';
        case InbodySheetRead(:final result):
          _applyParseResult(result);
      }
    });
  }

  /// setState 안에서 부른다 — 상태만 바꾼다.
  void _applyParseResult(InbodySheetParseResult result) {
    for (final entry in result.values.entries) {
      _controllers[entry.key]!.text = InbodyMetric.formatValue(entry.value);
      _prefilled.add(entry.key);
    }
    var dateApplied = false;
    if (result.measuredDate case final read?) {
      // 데이트피커와 같은 경계(2년 전~오늘) 밖이면 버린다 — 인쇄 연도를 오독한
      // 값으로 기본값(오늘)을 밀어내지 않는다.
      final today = DateFmt.todayKst();
      final first = DateTime(today.year - 2, today.month, today.day);
      if (!read.isBefore(first) && !read.isAfter(today)) {
        _date = read;
        dateApplied = true;
      }
    }
    _error = null;
    if (result.values.isEmpty) {
      _readNote = dateApplied
          ? '사진에서 측정일만 읽었어요 — 숫자는 직접 입력해주세요'
          : '사진에서 값을 읽지 못했어요 — 결과지를 다시 찍거나 직접 입력해주세요';
    } else {
      // 과장 금지: 실측에서 오인식이 실제로 났다(P20). 확인을 요청하는 문장은
      // 항상 붙는다 — 6칸을 다 채웠어도.
      _readNote =
          '사진에서 ${result.values.length}칸을 채웠어요. 읽은 값은 꼭 확인해주세요 — '
          '사진 상태에 따라 틀리거나 비어 있을 수 있어요';
    }
  }

  Future<InbodyPhotoSource?> _pickPhotoSource() {
    return showRiseSheet<InbodyPhotoSource>(
      context,
      isScrollControlled: false,
      // 이 시트는 종전부터 `SafeArea`로 하단을 스스로 처리해 왔다 — 래퍼는
      // `viewInsets`만 손대고 `SafeArea`는 `padding`을 읽으므로 겹치지 않는다.
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                '결과지 사진 고르기',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                // 결과지엔 이름·나이·성별이 함께 인쇄된다 — 무엇을 하는지 정확히.
                '사진은 숫자를 읽는 데만 쓰고 저장하지 않아요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, size: 20),
              title: const Text('앨범에서 선택', style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(sheetContext).pop(InbodyPhotoSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, size: 20),
              title: const Text('카메라로 촬영', style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(sheetContext).pop(InbodyPhotoSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 카메라 촬영 전 권한 게이트. 매니페스트에 CAMERA가 선언된 앱이라(P11)
  /// 권한 없이 촬영 인텐트를 띄우면 Android가 SecurityException을 던진다 —
  /// image_picker에 맡기지 않고 기존 게이트(core/permissions)로 먼저 통과시킨다.
  Future<bool> _ensureCameraPermission() async {
    final gate = ref.read(cameraPermissionGateProvider);
    final result = await gate.ensureGranted();
    // unsupported(플러그인 없음)는 막지 않는다 — image_picker가 실패하면 "읽지
    // 못했어요"로 떨어진다(qr_scan_screen과 같은 규약: 앱이 서버·OS보다 먼저
    // 판정하지 않는다).
    if (result == CameraPermissionResult.granted || result == CameraPermissionResult.unsupported) {
      return true;
    }
    if (!mounted) return false;
    final retry = await showRiseSheet<bool>(
      context,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        child: CameraPermissionView(
          result: result,
          // 시트는 밝은 카드다 — 프리뷰용 검정 배경을 깔지 않는다.
          dark: false,
          purpose: '결과지를 촬영하려면',
          // 용도별 사실 한 문장(camera_permission_view 규약): OCR은 저장하지 않는다.
          note: '결과지 사진은 숫자를 읽는 데만 쓰고 저장하지 않아요',
          onRetry: () => Navigator.of(sheetContext).pop(true),
          onOpenSettings: () {
            unawaited(gate.openSettings());
            Navigator.of(sheetContext).pop(false);
          },
          onCancel: () => Navigator.of(sheetContext).pop(false),
        ),
      ),
    );
    if (retry == true && mounted) return _ensureCameraPermission();
    return false;
  }

  static String? _helperFor(InbodyMetric metric) => switch (metric) {
    InbodyMetric.weight => null,
    InbodyMetric.smm => '골격근량',
    // 체/제 한 글자 차이에 단위가 둘 다 kg라 결과지를 옮겨 적을 때 실제로
    // 섞인다(backend/internal/domain/measurement.go가 사람 입력자에게 하는
    // 것과 같은 경고). 상시 노출한다 — 틀린 뒤에 말하면 늦다.
    InbodyMetric.bfm => '체지방량 — 제지방량(FFM) 아니에요',
    InbodyMetric.pbf => '체지방률',
    // 770/970 계열 결과지는 같은 자리에 내장지방 '단면적'(cm², 100 근처)을
    // 인쇄해 그대로 옮겨 적는 실수가 실제로 난다. 서버는 범위 초과 400에
    // 같은 힌트를 붙이지만(measurement.go), 앱이 같은 범위를 사전 판정해
    // 요청이 아예 안 나가므로 그 문구가 회원에게 닿을 길이 없다 — 여기
    // 상시 노출이 그 힌트의 유일한 전달 경로다(BFM 헬퍼와 같은 판단).
    InbodyMetric.vfl => '내장지방 레벨 — 단면적(cm²) 아니에요',
    InbodyMetric.bmr => '기초대사량',
  };

  Future<void> _pickDate() async {
    final today = DateFmt.todayKst();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // 2년 전까지 — 결과지를 몰아서 입력하는 경우를 막지 않는다.
      firstDate: DateTime(today.year - 2, today.month, today.day),
      // 미래는 고를 수 없다. 아직 측정하지 않은 날의 기록은 존재할 수 없고,
      // 오늘보다 뒤인 날짜가 들어가면 추이 그래프의 마지막 점이 되어 이후
      // 실제 측정이 그 앞에 끼어 들어간다.
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final raw = _raw;
    final draft = InbodyInputRules.draft(date: _date, raw: raw);
    // 버튼이 이미 잠기지만 이중 방어 — 위젯 배치가 바뀌어도 서버가 거부할
    // 요청은 나가지 않는다(hold_request_sheet과 같은 관문).
    if (draft == null) {
      final String message;
      if (!InbodyInputRules.isComplete(raw)) {
        message = '6개 항목을 모두 입력해주세요 — 결과지에 있는 숫자를 그대로 옮겨 적어주세요';
      } else if (InbodyInputRules.crossFieldError(raw) case final cross?) {
        message = cross;
      } else {
        message = '범위를 벗어난 값이 있어요 — 붉게 표시된 칸을 고쳐주세요';
      }
      setState(() => _error = message);
      return;
    }
    setState(() {
      widget.submitting.value = true;
      _error = null;
    });

    final result = await ref.read(recordsViewModelProvider.notifier).createInbody(draft);
    if (!mounted) return;
    switch (result) {
      case Ok():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(riseSnackBar('인바디 기록을 저장했어요', kind: RiseSnackKind.ok));
      case Err(:final failure):
        // 실패면 시트를 닫지 않는다 — 6칸을 다시 채우게 만들지 않기 위해서다.
        setState(() {
          widget.submitting.value = false;
          _error = failure.message;
        });
    }
  }
}

/// 소수점 1자리까지의 양수만 통과시킨다(정수부 4자리 = BMR 5000까지).
/// 붙여넣기까지 같은 규칙으로 걸러서, 필드에 애초에 파싱 불가한 문자열이 남지 않는다.
const _decimalOnePlace = _DecimalTextInputFormatter();

class _DecimalTextInputFormatter extends TextInputFormatter {
  const _DecimalTextInputFormatter();

  static final _pattern = RegExp(r'^\d{0,4}(\.\d?)?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty || _pattern.hasMatch(newValue.text)) return newValue;
    return oldValue;
  }
}

/// 시트 공통 껍데기 — 키보드가 올라와도 내용이 잘리지 않게 인셋만큼 띄운다.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: child,
    );
  }
}

/// 민감정보 동의가 없을 때 — **폼을 띄우지 않는다.**
///
/// 폼을 띄워 놓고 제출 순간에만 거부하면 회원은 숫자 6개를 다 옮겨 적은 뒤에야
/// 안 된다는 걸 알게 된다(hold_request_sheet의 `_NoCandidateBody`와 같은 판단).
class _ConsentRequiredBody extends StatelessWidget {
  const _ConsentRequiredBody();

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('인바디 기록 추가', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            '인바디 기록에는 민감정보 동의가 필요해요 — 마이 탭에서 동의해주세요',
            style: TextStyle(fontSize: 12, color: AppColors.danger, height: 1.5),
          ),
          const SizedBox(height: 14),
          RiseButton(
            label: '닫기',
            expand: true,
            style: RiseButtonStyleKind.outline,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap});
  final DateTime value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('측정일', style: TextStyle(fontSize: 9.5, color: AppColors.muted)),
            Text(
              DateFmt.isoDate(value),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
