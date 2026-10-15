import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_provider.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_uploader.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';
import 'package:rise_member/features/bodycheck/domain/body_photo_storage_path.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/bodycheck/presentation/body_camera_provider.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_view_model.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

// 촬영 → **회원 확인** → Storage 업로드 → POST /v1/body-photos 순서와 **실패 복구**를
// 못 박는다.
//
// 확인 단계는 v2.15에서 들어왔다(람 요청). 그전에는 셔터가 눌리는 즉시 서버로 갔는데,
// 자동 촬영은 사람이 프레임 안에 있는지 알 방법이 없어(수평만 본다) 책상에 세워 둔
// 폰이 빈 방을 찍어 그대로 올렸다 — 실기기에서 버킷에 쓰레기가 50장 쌓였다.
// 체형사진은 P8 민감정보라 **한 번 올라가면 지워도 "올라갔던 사실"은 되돌릴 수 없다.**
//
// 그래서 아래 대부분의 테스트는 `captureAndSave()`(찍고 확인까지)를 쓰고, 확인 단계
// 자체의 계약은 「찍고 나서 확인」 그룹이 따로 잠근다.
//
// 종전엔 이미지 바이너리를 아예 안 보내고 storage_path에 스텁 문자열을 넣었다.
// 이제 두 단계로 나뉘므로 새 실패 모드가 둘 생겼다:
//   ① Storage는 실패했는데 서버엔 기록되는 경우 → 서버에 죽은 경로가 남는다.
//   ② Storage는 성공했는데 서버 기록이 실패하는 경우 → 재시도가 같은 바이트를
//      두 번 올리면 안 되고, 경로도 새로 만들면 안 된다(버킷에 유령 파일).
void main() {
  final bytes = Uint8List.fromList(List<int>.filled(16, 7));

  late _FakeUploader uploader;
  late _FakeBodyCheckRepository repo;
  late _CountingRecordsRepository records;

  ProviderContainer make({bool sensitiveConsent = true, Uint8List? captured}) {
    uploader = _FakeUploader();
    repo = _FakeBodyCheckRepository();
    records = _CountingRecordsRepository();
    final container = ProviderContainer.test(
      overrides: [
        bodyPhotoUploaderProvider.overrideWithValue(uploader),
        bodyCheckRepositoryProvider.overrideWithValue(repo),
        recordsRepositoryProvider.overrideWithValue(records),
        bodyCameraProvider.overrideWith(() => _FakeBodyCamera(captured)),
        myProfileProvider.overrideWith(
          (ref) async => MemberDto(
            id: 'm1',
            name: '람',
            phone: '01012345678',
            consent: ConsentDto(general: true, sensitive: sensitiveConsent),
          ),
        ),
      ],
    );
    // **구독을 붙여 둔다.** `cameraViewModelProvider`는 autoDispose라 리스너가 없으면
    // 이벤트 큐가 비는 사이 폐기되고, 다음 `read`가 **새 기본 상태**를 만든다.
    // 확인 단계가 들어오면서 `capture()`와 `confirmReview()` 사이에 await 경계가
    // 생겼는데, 그 틈에 폐기되면 손에 든 사진이 사라져 저장이 조용히 실패한다
    // (실제로 이 스위트가 그렇게 깨졌다).
    container.listen(cameraViewModelProvider, (_, __) {});
    container.read(sessionProvider.notifier).set(
          const AppSession(
            uid: 'firebase-uid-1',
            role: 'member',
            centerId: 'rise-gangnam',
            memberId: 'm1',
            memberName: '람',
          ),
        );
    return container;
  }

  /// 찍고 **확인까지** — 종전 `capture()`가 하던 일 전체.
  /// 확인 단계를 검사하는 테스트만 `capture()`/`confirmReview()`를 따로 부른다.
  Future<void> captureAndSaveOn(CameraViewModel vm) async {
    await vm.capture();
    await vm.confirmReview();
  }

  group('찍고 나서 확인 — 저장은 회원이 결정한다', () {
    test('찍기만 해서는 기기 밖으로 아무것도 나가지 않는다', () async {
      // 이 스위트의 존재 이유. P8 민감정보는 올라간 뒤에 지워도 "올라갔던 사실"이
      // 남는다 — 눈이 한 번 보고 통과시킨 것만 나가야 한다.
      final container = make(captured: bytes);
      final vm = container.read(cameraViewModelProvider.notifier);

      await vm.capture();

      expect(uploader.calls, isEmpty, reason: 'Storage로 나갔다');
      expect(repo.lastStoragePath, isNull, reason: '서버로 나갔다');
      final state = container.read(cameraViewModelProvider);
      expect(state.review, isNotNull, reason: '확인할 사진을 손에 들고 있어야 한다');
      expect(state.review!.bytes, bytes, reason: '방금 찍은 그 바이트여야 한다');
      expect(state.submitting, isFalse);
      expect(state.completed, isEmpty, reason: '아직 저장된 게 아니다');
      expect(state.poseIndex, 0, reason: '확인 전에 다음 포즈로 넘어가면 안 된다');
    });

    test('"이 사진으로 저장"을 눌러야 올라간다', () async {
      final container = make(captured: bytes);
      final vm = container.read(cameraViewModelProvider.notifier);
      await vm.capture();

      await vm.confirmReview();

      expect(uploader.calls, hasLength(1));
      expect(uploader.calls.single.bytes, bytes);
      final state = container.read(cameraViewModelProvider);
      expect(state.review, isNull, reason: '확인이 끝났으면 검토 화면을 닫는다');
      expect(state.completed, contains('stand'));
    });

    test('"다시 찍기"는 아무것도 올리지 않고 버린다 — 지울 것이 없다', () async {
      final container = make(captured: bytes);
      final vm = container.read(cameraViewModelProvider.notifier);
      await vm.capture();

      vm.retakeReview();

      expect(uploader.calls, isEmpty, reason: '버린 사진이 버킷에 남으면 안 된다');
      expect(repo.lastStoragePath, isNull);
      final state = container.read(cameraViewModelProvider);
      expect(state.review, isNull);
      expect(state.completed, isEmpty);
    });

    test('"다시 찍기" 후 셔터를 다시 누르면 새로 찍힌다', () async {
      // 자동 촬영은 P31에서 제거했다(람 요청) — 이제 셔터가 유일한 경로이므로
      // "다시 찍기" 뒤에 그 경로가 막히지 않는지가 계약이다.
      final container = make(captured: bytes);
      container.listen(cameraViewModelProvider, (_, __) {});
      final vm = container.read(cameraViewModelProvider.notifier);

      await vm.capture();
      expect(container.read(cameraViewModelProvider).review, isNotNull);
      vm.retakeReview();
      expect(container.read(cameraViewModelProvider).review, isNull);

      await vm.capture();

      expect(container.read(cameraViewModelProvider).review, isNotNull,
          reason: '다시 찍기 후 셔터가 죽었다');
      expect(uploader.calls, isEmpty, reason: '확인 전인데 올라갔다');
    });

    test('확인 중에는 셔터를 눌러도 보던 사진이 갈아치워지지 않는다', () async {
      // 회원이 판단하는 동안 사진이 바뀌면, 본 것과 다른 사진을 저장하게 된다.
      final container = make(captured: bytes);
      container.listen(cameraViewModelProvider, (_, __) {});
      final vm = container.read(cameraViewModelProvider.notifier);
      await vm.capture();
      final held = container.read(cameraViewModelProvider).review;

      await vm.capture();

      expect(identical(container.read(cameraViewModelProvider).review, held), isTrue,
          reason: '보던 사진이 갈아치워졌다');
    });
  });

  group('성공 경로', () {
    test('Storage에 먼저 올리고, 서버에는 그 경로를 보낸다', () async {
      final container = make(captured: bytes);
      final vm = container.read(cameraViewModelProvider.notifier);

      await captureAndSaveOn(vm);

      expect(uploader.calls, hasLength(1));
      expect(uploader.calls.single.bytes, bytes);
      // 서버로 간 storage_path = 방금 올린 그 경로(스텁 문자열이 아니다).
      expect(repo.lastStoragePath, uploader.calls.single.path);
      // 경로 키는 memberId — 배포된 storage.rules가 대조하는 값(BodyPhotoStoragePath).
      expect(repo.lastStoragePath, startsWith('${BodyPhotoStoragePath.rootPrefix}/m1/${BodyPhotoStoragePath.folder}/'));

      final state = container.read(cameraViewModelProvider);
      expect(state.submitting, isFalse);
      expect(state.pendingRetry, isNull);
      expect(state.completed, contains('stand'));
      expect(state.poseIndex, 1, reason: '저장에 성공하면 다음 포즈로 넘어간다');
      expect(state.lastSavedMessage, '차렷 저장했어요');
    });
  });

  group('기준선', () {
    test('끌어 옮긴 뒤 초기화하면 기본 높이로 정확히 돌아온다', () {
      // 손으로 원위치를 찾는 건 정확히 맞출 수가 없다 — 되돌릴 길이 반드시 있어야 한다.
      final vm = make(captured: bytes).read(cameraViewModelProvider.notifier);

      vm.moveHLine(0.12);
      expect(vm.state.hLine, closeTo(0.12, 1e-9));

      vm.resetHLine();
      expect(vm.state.hLine, CameraState.defaultHLine);
    });

    test('프레임 밖으로는 못 나간다 — 선을 잃어버리면 다시 찾을 수가 없다', () {
      final vm = make(captured: bytes).read(cameraViewModelProvider.notifier);

      vm.moveHLine(-5);
      expect(vm.state.hLine, greaterThan(0.0));
      vm.moveHLine(5);
      expect(vm.state.hLine, lessThan(1.0));
    });
  });

  group('실패 경로 — 사진이 조용히 사라지지 않는다', () {
    test('Storage 업로드 실패 시 서버에 기록하지 않고, 사진을 손에 들고 재시도를 남긴다', () async {
      final container = make(captured: bytes);
      uploader.failure = const NetworkFailure('업로드 실패');
      final vm = container.read(cameraViewModelProvider.notifier);

      await captureAndSaveOn(vm);

      expect(repo.lastStoragePath, isNull, reason: 'Storage가 실패했는데 서버에 죽은 경로를 남기면 안 된다');
      final state = container.read(cameraViewModelProvider);
      expect(state.pendingRetry, isNotNull);
      expect(state.error, isA<NetworkFailure>());
      expect(state.completed, isEmpty);
      expect(state.poseIndex, 0, reason: '실패하면 다음 포즈로 넘어가지 않는다');
    });

    test('재시도는 같은 경로로 다시 올린다 — 버킷에 유령 파일을 만들지 않는다', () async {
      final container = make(captured: bytes);
      uploader.failure = const NetworkFailure('업로드 실패');
      final vm = container.read(cameraViewModelProvider.notifier);
      await captureAndSaveOn(vm);
      final firstPath = uploader.calls.single.path;

      uploader.failure = null;
      await vm.retryPendingUpload();

      expect(uploader.calls, hasLength(2));
      expect(uploader.calls[1].path, firstPath);
      expect(repo.lastStoragePath, firstPath);
      expect(container.read(cameraViewModelProvider).pendingRetry, isNull);
      expect(container.read(cameraViewModelProvider).completed, contains('stand'));
    });

    test('Storage는 됐는데 서버 기록이 실패하면, 재시도는 업로드를 다시 하지 않는다', () async {
      final container = make(captured: bytes);
      repo.failure = const NetworkFailure('서버 오류');
      final vm = container.read(cameraViewModelProvider.notifier);

      await captureAndSaveOn(vm);
      expect(uploader.calls, hasLength(1));
      expect(container.read(cameraViewModelProvider).pendingRetry, isNotNull);

      repo.failure = null;
      await vm.retryPendingUpload();

      expect(uploader.calls, hasLength(1), reason: '같은 바이트를 두 번 올리지 않는다');
      expect(container.read(cameraViewModelProvider).pendingRetry, isNull);
      expect(container.read(cameraViewModelProvider).completed, contains('stand'));
    });

    test('"버리기"를 누르면 재시도 배너와 에러가 함께 사라진다', () async {
      final container = make(captured: bytes);
      uploader.failure = const NetworkFailure('업로드 실패');
      final vm = container.read(cameraViewModelProvider.notifier);
      await captureAndSaveOn(vm);

      vm.discardPendingUpload();

      final state = container.read(cameraViewModelProvider);
      expect(state.pendingRetry, isNull);
      expect(state.error, isNull);
    });
  });

  // 촬영 시각은 **센터(KST) 벽시계**여야 한다. 이 값이 두 곳에 그대로 박히기 때문이다:
  //  ① Storage 경로의 날짜 앞머리(members/{id}/body/{yyyyMMdd}-…) — 배포된
  //     storage.rules가 날짜 폴더를 금지해 파일명에 날짜를 넣는 구조라, 로컬 시각이면
  //     해외에서 파일명 날짜가 서버 기록과 어긋난다(정렬=시간순 전제도 함께 깨진다).
  //  ② 서버로 가는 `date`(BodyCheckRepositoryImpl → DateFmt.isoDate).
  // 그리고 화면의 날짜 pill(camera_screen)도 같은 KST 오늘을 쓴다 — 셋이 갈리면
  // 회원은 화면에서 본 날짜와 다른 날짜로 저장된 사진을 나중에 찾지 못한다.
  //
  // ⚠️ 호스트가 KST면 `nowKst() == DateTime.now()`라 이 그룹은 회귀를 보지 못한다.
  //    `TZ=UTC` 등 KST 아닌 TZ로 돌리는 것까지가 검증이다(date_format_test 주석 참조).
  group('시간축 — 촬영 시각은 센터(KST)', () {
    test('서버로 가는 date가 KST 벽시계 — 로컬과의 간격이 정확히 (9시간 - 로컬오프셋)', () async {
      final container = make(captured: bytes);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));

      final wall = DateTime.now();
      final expectedGap = const Duration(hours: 9) - wall.timeZoneOffset;
      expect(repo.lastDate, isNotNull);
      expect(
        (repo.lastDate!.difference(wall) - expectedGap).abs() < const Duration(seconds: 5),
        isTrue,
        reason: 'capturedAt=${repo.lastDate}, now=$wall — 로컬 시각을 그대로 쓰고 있다',
      );
    });

    test('Storage 경로의 날짜 앞머리가 KST 오늘', () async {
      final container = make(captured: bytes);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));

      final today = DateFmt.todayKst();
      String pad(int v) => v.toString().padLeft(2, '0');
      final ymd = '${today.year}${pad(today.month)}${pad(today.day)}';

      expect(
        repo.lastStoragePath,
        startsWith('${BodyPhotoStoragePath.rootPrefix}/m1/${BodyPhotoStoragePath.folder}/$ymd-'),
        reason: '파일명 날짜가 서버 기록·화면 pill과 갈린다',
      );
    });

    test('경로의 날짜와 서버 date가 같은 날을 가리킨다', () async {
      final container = make(captured: bytes);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));

      final d = repo.lastDate!;
      String pad(int v) => v.toString().padLeft(2, '0');
      expect(repo.lastStoragePath, contains('/${d.year}${pad(d.month)}${pad(d.day)}-'));
    });
  });

  // 5개 탭이 StatefulShellRoute.indexedStack으로 동시에 mount된 채 유지되므로
  // (core/router/app_router.dart) 탭을 오가는 것만으로는 기록 탭의 AsyncData가
  // 폐기되지 않는다 — 방금 저장한 사진이 기록 탭에 안 나타나면 회원은 저장이
  // 안 된 줄 알고 다시 찍는다(중복 촬영·중복 저장). 홈→기록(toggleHomework)과
  // 같은 규약을 촬영→기록에도 적용한 것.
  group('업로드 성공은 기록 탭을 무효화한다 (indexedStack stale)', () {
    test('저장에 성공하면 기록 탭이 다시 로드된다', () async {
      final container = make(captured: bytes);
      // 기록 탭이 mount되어 있는 상황.
      container.listen(recordsViewModelProvider, (_, __) {});
      await container.read(recordsViewModelProvider.future);
      expect(records.loadCount, 1);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));
      await container.read(recordsViewModelProvider.future);

      expect(records.loadCount, 2, reason: '사진을 저장했는데 기록 탭이 "사진 없음"으로 남는다');
    });

    test('Storage 업로드가 실패하면 무효화하지 않는다 — 저장되지 않은 것으로 탭을 흔들 이유가 없다', () async {
      final container = make(captured: bytes);
      uploader.failure = const NetworkFailure('업로드 실패');
      container.listen(recordsViewModelProvider, (_, __) {});
      await container.read(recordsViewModelProvider.future);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));

      expect(records.loadCount, 1);
    });

    test('서버 기록이 실패해도 무효화하지 않는다', () async {
      final container = make(captured: bytes);
      repo.failure = const NetworkFailure('서버 오류');
      container.listen(recordsViewModelProvider, (_, __) {});
      await container.read(recordsViewModelProvider.future);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));

      expect(records.loadCount, 1);
    });
  });

  group('촬영 전 가드', () {
    test('민감정보 동의가 없으면 촬영도 업로드도 하지 않는다', () async {
      final container = make(sensitiveConsent: false, captured: bytes);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));

      expect(uploader.calls, isEmpty);
      expect(repo.lastStoragePath, isNull);
      expect(container.read(cameraViewModelProvider).error, isA<RejectedFailure>());
    });

    test('카메라가 준비되지 않아 바이트가 없으면 업로드하지 않고 안내만 띄운다', () async {
      final container = make(captured: null);

      await captureAndSaveOn(container.read(cameraViewModelProvider.notifier));

      expect(uploader.calls, isEmpty);
      expect(repo.lastStoragePath, isNull);
      final state = container.read(cameraViewModelProvider);
      expect(state.submitting, isFalse, reason: '스피너가 영원히 돌면 안 된다');
      expect(state.error, isA<RejectedFailure>());
    });
  });

  group('세션 소멸 — 조용한 return 금지, 사진은 잃지 않고 이유는 말한다(P64)', () {
    // 셸이 떠 있는 채 세션이 비는 순간(401·로그아웃·탈퇴·재검증 미연결)에 회원이 탭한
    // [이 사진으로 저장]은 종전엔 아무 피드백 없이 끝났다. 바이트는 그대로 두고
    // 타입 있는 실패만 세운다 — 화면은 이 타입을 전환 중으로 그린다.

    test('검토 중 세션이 비면 confirmReview는 review 바이트를 보존한 채 SessionGoneFailure를 세운다',
        () async {
      final container = make(captured: bytes);
      final vm = container.read(cameraViewModelProvider.notifier);
      await vm.capture();
      final held = container.read(cameraViewModelProvider).review;
      expect(held, isNotNull);

      container.read(sessionProvider.notifier).clear(reason: SessionEndReason.unauthorized);
      await vm.confirmReview();

      final state = container.read(cameraViewModelProvider);
      expect(state.error, isA<SessionGoneFailure>(), reason: '조용히 끝났다 — 이유가 없다');
      expect(identical(state.review, held), isTrue, reason: '손에 든 사진을 잃었다');
      expect(state.submitting, isFalse, reason: '스피너가 영원히 돌면 안 된다');
      expect(uploader.calls, isEmpty, reason: '세션 없이 Storage로 나갔다');
      expect(repo.lastStoragePath, isNull, reason: '세션 없이 서버로 나갔다');
    });

    test('재시도 대기 중 세션이 비면 retryPendingUpload는 pendingRetry를 보존한 채 SessionGoneFailure를 세운다',
        () async {
      final container = make(captured: bytes);
      uploader.failure = const NetworkFailure('업로드 실패');
      final vm = container.read(cameraViewModelProvider.notifier);
      await captureAndSaveOn(vm);
      final held = container.read(cameraViewModelProvider).pendingRetry;
      expect(held, isNotNull);
      final callsBefore = uploader.calls.length;

      container.read(sessionProvider.notifier).clear(reason: SessionEndReason.unauthorized);
      await vm.retryPendingUpload();

      final state = container.read(cameraViewModelProvider);
      expect(state.error, isA<SessionGoneFailure>());
      expect(identical(state.pendingRetry, held), isTrue, reason: '재시도할 사진을 잃었다');
      expect(state.submitting, isFalse);
      expect(uploader.calls.length, callsBefore, reason: '세션 없이 다시 올렸다');
    });

    // 저장 왕복(스피너)이 도는 동안 화면이 내려가는 경로가 실재한다: 세션 리스너가
    // 전체화면 라우트째 내리거나, 회원이 확인 대화상자에서 "나가기"를 고른다. 그때
    // await 뒤의 `state =`는 상태를 갱신하는 게 아니라 **던진다** — 업로드 실패가
    // 화면에 닿지도 못한 채 zone error로 샌다.
    //
    // 뮤테이션: `_persist`의 `if (!ref.mounted) return;`을 지우면 이 테스트가 죽는다.
    test('저장 왕복 중 화면이 내려가도 조용히 끝난다 — 폐기된 ref에 쓰지 않는다', () async {
      final container = make(captured: bytes);
      final vm = container.read(cameraViewModelProvider.notifier);
      await vm.capture();

      final gate = Completer<void>();
      uploader.gate = gate;
      final saving = vm.confirmReview();
      await Future<void>.value();

      container.dispose();
      gate.complete();

      await expectLater(saving, completes);
    });

    test('세션 없이 셔터를 누르면 찍지 않고 SessionGoneFailure를 세운다', () async {
      final container = make(captured: bytes);
      // 뷰모델은 `myProfileProvider`를 watch한다 — 프로필 future가 **이 테스트 도중**
      // 처음 풀리면 뷰모델이 재빌드되어 방금 세운 error가 기본 상태로 씻긴다(위 두
      // 테스트는 `capture()`가 프로필을 기다리는 동안 그 재빌드를 지나간다). 프로필을
      // 먼저 안착시켜 재빌드를 셔터 **앞**으로 보낸다 — 실기기의 순서와 같다(촬영
      // 화면은 프로필이 캐시된 뒤 열린다).
      await container.read(myProfileProvider.future);
      container.read(sessionProvider.notifier).clear(reason: SessionEndReason.unauthorized);

      await container.read(cameraViewModelProvider.notifier).capture();

      final state = container.read(cameraViewModelProvider);
      expect(state.error, isA<SessionGoneFailure>(), reason: '셔터에 반응이 없다');
      expect(state.review, isNull, reason: '세션 없이 찍혔다');
      expect(state.submitting, isFalse);
    });
  });
}

class _UploadCall {
  const _UploadCall(this.path, this.bytes);
  final String path;
  final Uint8List bytes;
}

class _FakeUploader implements BodyPhotoUploader {
  final calls = <_UploadCall>[];
  Failure? failure;

  /// 업로드를 **왕복 중간에 붙잡아 두는** 문. 화면이 내려가는 순간을 그 사이에
  /// 끼워 넣으려면 실제 네트워크처럼 아직 안 끝난 구간이 있어야 한다.
  Completer<void>? gate;

  @override
  Future<Result<String>> upload({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    calls.add(_UploadCall(storagePath, bytes));
    await gate?.future;
    final f = failure;
    return f == null ? Ok(storagePath) : Err(f);
  }
}

class _FakeBodyCheckRepository implements BodyCheckRepository {
  // 이 스위트는 삭제 경로를 쓰지 않는다 — 부르면 조용히 통과하는 대신 터뜨려서
  // "안 부른다"는 전제가 깨졌을 때 바로 드러나게 한다.
  @override
  Future<Result<void>> deletePhoto({required String id, String? storagePath}) =>
      throw UnimplementedError();

  String? lastStoragePath;

  /// 서버로 가는 촬영 시각 — `BodyCheckRepositoryImpl`이 `DateFmt.isoDate`로 찍어
  /// 보내는 바로 그 값(시간축 검증의 관측점).
  DateTime? lastDate;
  Failure? failure;

  @override
  Future<Result<List<BodyPhotoEntry>>> fetchPhotos(String memberId) async => const Ok([]);

  @override
  Future<Result<BodyPhotoEntry>> uploadPhoto({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime date,
    required String storagePath,
  }) async {
    final f = failure;
    if (f != null) return Err(f);
    lastStoragePath = storagePath;
    lastDate = date;
    return Ok(BodyPhotoEntry(
      id: 'bp1',
      memberId: memberId,
      pose: pose,
      direction: direction,
      date: date,
      storagePath: storagePath,
      blurred: false,
    ));
  }
}

/// 기록 탭이 몇 번 다시 로드됐는지만 센다 — 무효화가 실제로 일어났는지의 유일한 증거.
class _CountingRecordsRepository implements RecordsRepository {
  int loadCount = 0;

  @override
  Future<Result<RecordsData>> load(String memberId) async {
    loadCount++;
    return const Ok(RecordsData(
      workoutLogs: [],
      homeworkWeeks: [],
      inbodyRecords: [],
      bodyPhotos: BodyPhotoAlbum.empty,
    ));
  }

  // 이 테스트는 촬영 경로만 본다 — 인바디 쓰기가 여기서 호출되면 그건 결함이므로
  // 조용한 no-op이 아니라 즉시 실패로 드러낸다.
  @override
  Future<Result<void>> createInbody({required String memberId, required InbodyDraft draft}) =>
      throw UnsupportedError('촬영 경로가 인바디를 저장하지 않는다');

  @override
  Future<Result<void>> deleteInbody(String id) =>
      throw UnsupportedError('촬영 경로가 인바디를 삭제하지 않는다');
}

/// 실 하드웨어 대신 미리 정한 바이트를 돌려주는 카메라.
/// [captured]가 null이면 "준비 안 됨"(실패 경로).
class _FakeBodyCamera extends BodyCamera {
  _FakeBodyCamera(this.captured);
  final Uint8List? captured;

  @override
  Future<BodyCameraState> build() async =>
      const BodyCameraFailed('테스트 카메라'); // 프리뷰는 이 테스트의 관심사가 아니다.

  @override
  Future<Uint8List?> takeJpeg() async => captured;
}
