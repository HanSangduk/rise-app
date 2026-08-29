import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

// 체형 사진 앨범 — 촬영은 4종, 조회는 1종이던 비대칭을 없앤 뒤의 도메인 규칙.
//
// 카메라는 `PoseSpec.fallbackSequence` 4종(차렷·T자·전굴·OH스쿼트)을 전부 찍게 하는데
// 기록 탭은 데이터 계층에서 `ohsquat`만 골라 타임라인을 만들었다 — 회원은 4장을
// 찍고 1장만 다시 볼 수 있었고, 나머지 3장은 저장은 되지만 앱 어디에도 나타나지
// 않았다. 게다가 ohsquat은 촬영 시퀀스의 **마지막**이라 도중에 그만둔 회원에겐
// 늘 0장이고, 첫 진입이 대개 "아직 촬영한 사진이 없어요"였다.
void main() {
  BodyPhotoEntry photo(String pose, int day) => BodyPhotoEntry(
        id: '$pose$day',
        memberId: 'm1',
        pose: pose,
        direction: BodyDirection.front,
        date: DateTime(2026, 8, day),
        blurred: false,
      );

  group('묶기', () {
    test('포즈별로 나뉘고 각 포즈 안은 오래된 순', () {
      final album = BodyPhotoAlbum.from([
        photo('stand', 21),
        photo('tpose', 14),
        photo('stand', 7),
      ]);

      expect(album.entriesFor('stand').map((e) => e.id), ['stand7', 'stand21']);
      expect(album.entriesFor('tpose').map((e) => e.id), ['tpose14']);
      expect(album.entriesFor('fold'), isEmpty);
      expect(album.totalCount, 3);
    });

    test('한 장도 없으면 isEmpty — 4종 모두 0장', () {
      expect(BodyPhotoAlbum.from(const []).isEmpty, isTrue);
      expect(BodyPhotoAlbum.empty.isEmpty, isTrue);
      for (final pose in PoseSpec.fallbackSequence) {
        expect(BodyPhotoAlbum.empty.countFor(pose.key), 0);
      }
    });

    test('한 포즈라도 있으면 isEmpty가 아니다 — ohsquat이 비어도 마찬가지', () {
      final album = BodyPhotoAlbum.from([photo('stand', 1)]);

      expect(album.isEmpty, isFalse);
      expect(album.countFor('ohsquat'), 0);
    });
  });

  group('첫 진입 포즈(defaultPose)', () {
    test('사진이 가장 많은 포즈 — 비교(2장 이상)가 성립할 확률이 가장 높은 쪽', () {
      final album = BodyPhotoAlbum.from([
        photo('stand', 1),
        photo('fold', 1),
        photo('fold', 2),
        photo('fold', 3),
      ]);

      expect(album.defaultPose(PoseSpec.fallbackSequence), 'fold');
    });

    test('ohsquat 고정이 아니다 — stand만 찍은 회원이 "사진 없음"을 보면 안 된다', () {
      final album = BodyPhotoAlbum.from([photo('stand', 1), photo('stand', 2)]);

      expect(album.defaultPose(PoseSpec.fallbackSequence), 'stand');
      expect(album.entriesFor(album.defaultPose(PoseSpec.fallbackSequence)), isNotEmpty);
    });

    test('ohsquat이 최다면 ohsquat — 종전 기본값도 데이터가 맞으면 그대로 나온다', () {
      final album = BodyPhotoAlbum.from([
        photo('stand', 1),
        photo('ohsquat', 1),
        photo('ohsquat', 2),
      ]);

      expect(album.defaultPose(PoseSpec.fallbackSequence), 'ohsquat');
    });

    test('동수면 촬영 순서(PoseSpec.fallbackSequence)에서 앞선 쪽 — 새로고침마다 흔들리지 않게', () {
      final album = BodyPhotoAlbum.from([photo('ohsquat', 1), photo('tpose', 1)]);

      expect(album.defaultPose(PoseSpec.fallbackSequence), 'tpose');
    });

    test('전부 0장이면 촬영이 시작되는 포즈(차렷)', () {
      expect(BodyPhotoAlbum.empty.defaultPose(PoseSpec.fallbackSequence), 'stand');
      expect(BodyPhotoAlbum.empty.defaultPose(PoseSpec.fallbackSequence),
          PoseSpec.fallbackSequence.first.key);
    });

    test('사진이 하나라도 있으면 defaultPose는 절대 빈 포즈가 아니다', () {
      for (final pose in PoseSpec.fallbackSequence) {
        final album = BodyPhotoAlbum.from([photo(pose.key, 1)]);
        expect(album.entriesFor(album.defaultPose(PoseSpec.fallbackSequence)), isNotEmpty, reason: '${pose.key} 한 장짜리 앨범');
      }
    });
  });

  test('timelineFor는 그 포즈의 타임라인을 준다', () {
    final album = BodyPhotoAlbum.from([photo('tpose', 1), photo('stand', 2)]);

    final timeline = album.timelineFor('tpose');

    expect(timeline.pose, 'tpose');
    expect(timeline.entries.map((e) => e.id), ['tpose1']);
  });
}
