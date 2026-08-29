import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/domain/body_photo_storage_path.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';

// 체형 사진은 P8 민감정보이고, 경로 형태는 **이미 배포된 storage.rules**가 정했다:
//
//   match /members/{memberId}/body/{fileName}
//     allow create, update: if myMemberId() == memberId && hasSensitiveConsent(...)
//
// 세그먼트가 하나라도 늘거나 줄면 이 match가 빗나가고, 그러면 맨 아래 전면 차단
// 규칙에 걸려 업로드가 403으로 조용히 막힌다 — 앱에서는 "네트워크 오류"처럼 보인다.
// 그래서 형태를 테스트로 고정한다.
void main() {
  final at = DateTime(2026, 8, 23, 14, 5, 6);

  String build({
    String memberId = 'm-001',
    String pose = 'stand',
    BodyDirection direction = BodyDirection.front,
  }) =>
      BodyPhotoStoragePath.build(
        memberId: memberId,
        pose: pose,
        direction: direction,
        capturedAt: at,
      );

  group('규칙이 매칭하는 경로 형태', () {
    test('members/{memberId}/body/{fileName} — 세그먼트 정확히 4개', () {
      final segments = build().split('/');

      expect(segments.length, 4, reason: '날짜 폴더를 파면 {fileName} 와일드카드가 빗나간다');
      expect(segments[0], 'members');
      expect(segments[1], 'm-001');
      expect(segments[2], 'body');
      expect(segments[3], '20260823-stand-front-${at.millisecondsSinceEpoch}.jpg');
    });

    test('날짜는 폴더가 아니라 파일명 앞머리 — 이름순 정렬이 곧 시간순', () {
      final earlier = BodyPhotoStoragePath.build(
        memberId: 'm',
        pose: 'stand',
        direction: BodyDirection.front,
        capturedAt: DateTime(2026, 1, 2),
      );
      final later = BodyPhotoStoragePath.build(
        memberId: 'm',
        pose: 'stand',
        direction: BodyDirection.front,
        capturedAt: DateTime(2026, 11, 2),
      );

      expect(earlier.split('/')[3], startsWith('20260102-'));
      expect(later.split('/')[3], startsWith('20261102-'));
      expect(earlier.compareTo(later), lessThan(0));
    });

    test('포즈·방향은 계약의 wire 값 그대로', () {
      expect(build(pose: 'ohsquat', direction: BodyDirection.side),
          contains('-ohsquat-side-'));
    });

    test('확장자는 jpg — 규칙의 contentType image/* 와 짝', () {
      expect(build(), endsWith('.jpg'));
    });
  });

  group('memberId 정규화 — 세그먼트 수가 흔들리지 않게', () {
    test('슬래시가 섞여도 폴더를 더 파지 않는다', () {
      final path = build(memberId: 'm1/../m2');
      expect(path.split('/').length, 4);
      expect(path.split('/')[1], 'm1m2');
    });

    test('전부 깎여 빈 문자열이 되면 unknown으로 떨어진다(빈 세그먼트 금지)', () {
      expect(build(memberId: '///').split('/')[1], 'unknown');
    });

    test('영숫자·하이픈·언더바는 보존', () {
      expect(build(memberId: 'mem_ID-01').split('/')[1], 'mem_ID-01');
    });
  });

  test('같은 날 같은 포즈를 다시 찍으면 다른 파일 — 앞 사진을 덮지 않는다', () {
    String at2(DateTime t) => BodyPhotoStoragePath.build(
          memberId: 'm',
          pose: 'stand',
          direction: BodyDirection.front,
          capturedAt: t,
        );

    expect(at2(DateTime(2026, 8, 23, 10)), isNot(at2(DateTime(2026, 8, 23, 10, 0, 1))));
  });

  test('업로드 상한은 규칙의 10MB와 같다', () {
    expect(BodyPhotoStoragePath.maxUploadBytes, 10 * 1024 * 1024);
  });
}
