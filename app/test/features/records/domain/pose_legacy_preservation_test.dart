// 회원별 포즈 시퀀스(계약 v2.10)에서 **이미 찍은 사진이 사라지지 않는가**.
//
// 포즈가 회원마다 달라지면서 생긴 새 위험이다: 대표가 어드민에서 포즈를 빼거나 커스텀으로
// 갈아끼우는 순간, 그 포즈로 찍힌 옛 사진들이 앱에서 통째로 안 보이게 될 수 있다.
// 체형사진에는 삭제 API가 없으므로(계약: `allow delete: if false`) 안 보이면 영영 못 본다.
//
// 종전 코드의 `BodyPose.fromWire`는 모르는 key를 `stand`로 떨어뜨렸는데, 그러면 사라지는
// 대신 **남의 포즈 앨범에 뒤섞인다** — 더 나쁘다. 지금은 key 원문을 보존하고 라벨만 폴백한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

BodyPhotoEntry photo(String pose, int day) => BodyPhotoEntry(
      id: '$pose$day',
      memberId: 'm1',
      pose: pose,
      direction: BodyDirection.front,
      date: DateTime(2026, 8, day),
      blurred: false,
    );

void main() {
  group('시퀀스가 바뀌어도 옛 사진은 보인다', () {
    // 대표가 기본 4종 → 커스텀 2종으로 갈아끼운 상황.
    const newSequence = [
      PoseSpec('front_relax', '정면 이완'),
      PoseSpec('side_left', '좌측면'),
    ];

    test('시퀀스에서 빠진 포즈도 칩 목록에 남는다(뒤쪽에)', () {
      final album = BodyPhotoAlbum.from([
        photo('stand', 1), // 옛 시퀀스로 찍은 사진
        photo('front_relax', 2), // 새 시퀀스로 찍은 사진
      ]);

      final keys = album.poseKeys(newSequence);

      // 새 시퀀스가 앞 — 회원이 "지금 찍어야 할 포즈"가 먼저 보여야 한다.
      expect(keys.take(2), ['front_relax', 'side_left']);
      // 빠진 포즈는 뒤에 남는다 — 사라지면 그 사진을 여는 길이 없다.
      expect(keys, contains('stand'));
      expect(album.countFor('stand'), 1, reason: '옛 사진이 사라졌다');
    });

    test('빠진 포즈의 라벨은 레거시 맵으로 복원된다(raw key 노출 방지)', () {
      expect(PoseSpec.labelFor('stand', sequence: newSequence), '차렷');
      expect(PoseSpec.labelFor('ohsquat', sequence: newSequence), 'OH스쿼트');
    });

    test('시퀀스에 있으면 시퀀스 라벨이 이긴다(대표가 정한 이름)', () {
      expect(PoseSpec.labelFor('front_relax', sequence: newSequence), '정면 이완');
    });

    test('아무 데도 없는 key는 raw로 보여준다 — stand로 떨어뜨리지 않는다', () {
      // 종전 fromWire 폴백이 하던 짓: 모르는 key → stand.
      // 그러면 이 사진이 차렷 앨범에 섞여 "안 찍은 사진이 있는" 것처럼 보인다.
      expect(PoseSpec.labelFor('unknown_pose', sequence: newSequence), 'unknown_pose');

      final album = BodyPhotoAlbum.from([photo('unknown_pose', 3)]);
      expect(album.countFor('stand'), 0, reason: '미지 포즈가 차렷으로 오분류됐다');
      expect(album.countFor('unknown_pose'), 1);
      expect(album.poseKeys(newSequence), contains('unknown_pose'));
    });

    test('defaultPose는 사진이 있는 포즈를 고른다 — 빠진 포즈여도', () {
      // 새 시퀀스 포즈는 아직 0장이고 옛 포즈에만 사진이 있는 상태
      // (대표가 방금 포즈를 바꾼 직후의 모든 회원이 이 상태다).
      final album = BodyPhotoAlbum.from([photo('stand', 1), photo('stand', 2)]);
      expect(album.defaultPose(newSequence), 'stand',
          reason: '첫 진입이 빈 포즈면 "사진이 없어요"만 보인다');
    });
  });

  group('빈 시퀀스·빈 앨범 경계', () {
    test('시퀀스가 비어도 사진 key로 목록이 선다', () {
      final album = BodyPhotoAlbum.from([photo('stand', 1)]);
      expect(album.poseKeys(const []), ['stand']);
      expect(album.defaultPose(const []), 'stand');
    });

    test('사진도 시퀀스도 없으면 폴백 첫 포즈', () {
      expect(BodyPhotoAlbum.empty.defaultPose(const []),
          PoseSpec.fallbackSequence.first.key);
    });
  });
}
