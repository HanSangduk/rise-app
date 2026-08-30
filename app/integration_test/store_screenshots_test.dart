// 스토어 스크린샷 캡처(P46) — 시드된 로컬 백엔드(DEV_SEED=true) + Firebase 테스트
// 번호로 로그인해 주요 화면을 순회하며 takeScreenshot으로 저장한다.
//
// 실행(전체 절차는 store/screenshots/capture.sh):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/store_screenshots_test.dart -d <device-id> \
//     --dart-define=API_BASE_URL=http://localhost:8081 \
//     --dart-define=DEMO_PHOTO_BASE=http://localhost:8082
//
// live_flow_test와 같은 골격이지만 목적이 다르다 — 그쪽은 프로덕션 실플로우 점검,
// 이쪽은 **시드 데이터가 가장 보기 좋은 상태**(김민지: 패스 2·예약·홈워크·인바디·
// 수업기록·사진 코치 3명·체형 사진 4장)의 화면 수집이다.
//
// 체형 사진: 시드의 StoragePath("demo/*.jpg")를 실제 Firebase Storage가 아니라
// 캡처 하네스의 로컬 HTTP(store/demo-photos, 8082)에서 받는 데모 로더로 오버라이드
// 한다 — Storage 규칙은 프로덕션 Firestore 신원을 보므로 시드 회원의 사진을 실제
// 버킷에 올릴 방법이 없다(있어도 P8 민감정보 자리에 데모 파일을 올리면 안 된다).
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/app.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';
import 'package:rise_member/firebase_options.dart';

const demoPhotoBase = String.fromEnvironment(
  'DEMO_PHOTO_BASE',
  defaultValue: 'http://localhost:8082',
);

/// 데모 체형 사진 로더 — storage_path의 파일명을 로컬 HTTP에서 받는다.
class _DemoBodyPhotoLoader implements BodyPhotoLoader {
  final _cache = <String, Uint8List>{};

  @override
  Future<Result<Uint8List>> load(String storagePath) async {
    final hit = _cache[storagePath];
    if (hit != null) return Ok(hit);
    try {
      final name = storagePath.split('/').last;
      final client = HttpClient();
      final rsp = await client
          .getUrl(Uri.parse('$demoPhotoBase/$name'))
          .then((r) => r.close());
      final bytes = await consolidateHttpClientResponseBytes(rsp);
      client.close();
      _cache[storagePath] = bytes;
      return Ok(bytes);
    } catch (_) {
      return const Err(NetworkFailure('데모 사진 서버(8082)에 연결하지 못했어요'));
    }
  }

  @override
  Uint8List? peek(String storagePath) => _cache[storagePath];

  @override
  void evict(String storagePath) => _cache.remove(storagePath);

  @override
  void clear() => _cache.clear();
}

/// [finder]가 트리에 나타날 때까지(최대 [seconds]초) 프레임을 돌린다.
/// 고정 대기로는 기기별 속도차를 못 흡수한다 — Android 에뮬레이터에서 실측.
Future<bool> waitFor(WidgetTester tester, Finder finder, {int seconds = 20}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 250));
  }
  return false;
}

Future<void> settle(WidgetTester tester, {int seconds = 6}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 캡처 방식이 플랫폼마다 다르다.
  //
  // iOS: integration_test의 takeScreenshot(드라이버가 파일로 저장).
  //
  // Android: **adb exec-out screencap**을 호스트에서 찍는다. 에뮬레이터에서
  // `convertFlutterSurfaceToImage` + `takeScreenshot` 경로가
  // `IllegalArgumentException: Window doesn't have a backing surface!`로 앱을 죽인다
  // (PixelCopy가 서피스 전환 직후를 못 견딘다 — 실측). 마커를 로그로 흘리고 화면을
  // 잠시 붙들면 호스트 스크립트가 그 창에서 실캡처한다 — 실제 기기 화면이라
  // 오히려 정확하고, 앱을 죽이지 않는다.
  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400)); // 진입 애니메이션 정리
    if (Platform.isAndroid) {
      debugPrint('[CAPTURE] $name');
      await settle(tester, seconds: 4); // 호스트 캡처 창
      return;
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('스토어 스크린샷 순회', (tester) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyPhotoLoaderProvider.overrideWithValue(_DemoBodyPhotoLoader()),
        ],
        child: const RiseMemberApp(),
      ),
    );
    await settle(tester, seconds: 4);

    // ── 로그인 우회 — Firebase SMS 인증은 드라이브 하네스 안에서 완주가 안 된다
    // (reCAPTCHA/APNs 검증 경로가 헤드리스에서 멈춤 — 실측). 세션을 직접 심고
    // 홈으로 보낸다. API 신원은 dev 헤더(DEV_UID=member1)가 이미 시드 김민지를
    // 가리키므로, 이후 모든 화면은 실서버 데이터로 실동작한다.
    // 첫 화면(로그인 Scaffold)이 뜰 때까지 기다린다 — Android 에뮬레이터는 초기 렌더가
    // iOS 시뮬보다 느려 고정 대기로는 앵커를 못 찾는다(실측: Bad state: No element).
    for (var i = 0; i < 60 && find.byType(Scaffold).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final anchor = tester.element(find.byType(Scaffold).first);
    ProviderScope.containerOf(anchor).read(sessionProvider.notifier).set(
          const AppSession(
            uid: 'member1',
            role: 'member',
            centerId: 'rise',
            memberId: 'mem_000001',
            memberName: '김민지',
          ),
        );
    GoRouter.of(anchor).go('/home');

    // ── 01 홈(코치 카드·회원권·오늘 일정·Home Work)
    expect(await waitFor(tester, find.text('홈')), isTrue,
        reason: '홈 셸에 도착해야 한다');
    await settle(tester, seconds: 6); // 홈 데이터(패스·예약·홈워크·스태프) 로드
    await shot(tester, '01_home');

    // ── 02 예약
    await waitFor(tester, find.text('예약'));
    await tester.tap(find.text('예약').last);
    await settle(tester, seconds: 6);
    await shot(tester, '02_booking');

    // ── 03 기록(수업 기록) / 04 인바디(곡선 차트) / 05 체형 분석(사진 비교)
    await waitFor(tester, find.text('기록'));
    await tester.tap(find.text('기록').last);
    await settle(tester, seconds: 6);
    await shot(tester, '03_records');
    final inbodyChip = find.text('인바디');
    if (inbodyChip.evaluate().isNotEmpty) {
      await tester.tap(inbodyChip.first);
      await settle(tester, seconds: 4);
      await shot(tester, '04_inbody');
    }
    final bodyChip = find.text('체형 분석');
    if (bodyChip.evaluate().isNotEmpty) {
      await tester.tap(bodyChip.first);
      await settle(tester, seconds: 8); // 사진 4장 로드(로컬 HTTP)
      await shot(tester, '05_bodycheck');
    }

    // ── 06 마이(회원권·결제·계약)
    await waitFor(tester, find.text('마이'));
    await tester.tap(find.text('마이').last);
    await settle(tester, seconds: 6);
    await shot(tester, '06_my');

    // ── 07 센터 코치 소개(ASO 확정 7번 — 코치 프로필 단독 샷은 ASO 판정으로 제외)
    // 마이 탭은 지연 로딩 ListView라 하단 행이 트리에 없다 — 스크롤로 만들어 낸다
    // (ensureVisible은 이미 빌드된 위젯 전제라 여기선 무력. 1차 캡처에서 실측).
    final coaches = find.text('센터 코치 소개');
    await tester.scrollUntilVisible(coaches, 320,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(coaches.first);
    await settle(tester, seconds: 6); // 아바타 이미지 로드(외부 URL)
    await shot(tester, '07_coaches');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
