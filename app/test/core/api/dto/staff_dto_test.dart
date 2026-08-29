import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';

// P05 — Staff.profile(계약 v1.6) 파싱의 null 안전 규약:
// 계약상 서버는 항상 객체(배열은 [])를 주지만, 구버전 서버/키 누락/명시적 null에도
// 앱은 빈 프로필로 동작해야 한다(프로필 시트 "아직 소개가 등록되지 않았어요").
//
// + 계약 v2.0(직원 생애주기) — Staff.status/left_at 승격 규약:
// "필드 부재/""는 로드 시 active로 승격". 이걸 틀리면 구버전 서버 응답에서
// 센터 전원이 퇴사자로 표기되는(또는 그 반대의) 최악의 오표기가 난다.
void main() {
  group('StaffDto.fromJson — profile', () {
    test('전체 필드 파싱(v1.6 시딩 형태)', () {
      final dto = StaffDto.fromJson({
        'uid': 't1',
        'role': 'trainer',
        'name': '정혜린',
        'color': '#f43f5e',
        'profile': {
          'photo_url': '',
          'title': '퍼포먼스 트레이너',
          'career_years': 7,
          'specialties': ['여성 근력', '체형 교정'],
          'certifications': ['NASM-CPT'],
          'awards': ['피트니스 모델 그랑프리 2023 TOP5'],
          'bio': '여성 회원 비율 80%.',
        },
      });

      expect(dto.profile.title, '퍼포먼스 트레이너');
      expect(dto.profile.careerYears, 7);
      expect(dto.profile.specialties, ['여성 근력', '체형 교정']);
      expect(dto.profile.certifications, ['NASM-CPT']);
      expect(dto.profile.awards, hasLength(1));
      expect(dto.profile.bio, isNotEmpty);
      expect(dto.profile.isEmpty, isFalse);
    });

    test('profile 키 누락 → 빈 프로필(구버전 서버 호환)', () {
      final dto = StaffDto.fromJson({'uid': 't2', 'name': '김태오'});

      expect(dto.profile.isEmpty, isTrue);
      expect(dto.profile.photoUrl, '');
      expect(dto.profile.specialties, isEmpty);
    });

    test('profile: null → 빈 프로필(계약은 null 금지지만 방어)', () {
      final dto = StaffDto.fromJson({'uid': 't2', 'name': '김태오', 'profile': null});

      expect(dto.profile.isEmpty, isTrue);
    });

    test('profile 내부 필드 부분 누락 → 나머지는 기본값', () {
      final dto = StaffDto.fromJson({
        'uid': 'owner1',
        'name': '박관장',
        'profile': {'title': '대표 · 헤드 코치'},
      });

      expect(dto.profile.title, '대표 · 헤드 코치');
      expect(dto.profile.careerYears, 0);
      expect(dto.profile.awards, isEmpty);
      expect(dto.profile.isEmpty, isFalse);
    });
  });

  group('StaffDto.fromJson — status/left_at (계약 v2.0)', () {
    test('status 키 누락 → active(구버전 서버 전원이 퇴사로 보이면 안 된다)', () {
      final dto = StaffDto.fromJson({'uid': 't1', 'name': '정혜린'});

      expect(dto.status, 'active');
      expect(dto.isInactive, isFalse);
      expect(dto.leftAt, isNull);
      expect(dto.leftOn, isNull);
    });

    test('status: "" → active로 승격(계약 명문 규약)', () {
      final dto = StaffDto.fromJson({'uid': 't1', 'name': '정혜린', 'status': ''});

      expect(dto.isInactive, isFalse);
    });

    test('status: null → active(계약은 null 금지지만 방어)', () {
      final dto = StaffDto.fromJson({'uid': 't1', 'name': '정혜린', 'status': null});

      expect(dto.isInactive, isFalse);
    });

    test('모르는 status 값 → active(오표기보다 현직 표시가 안전)', () {
      final dto = StaffDto.fromJson({'uid': 't1', 'name': '정혜린', 'status': 'suspended'});

      expect(dto.isInactive, isFalse);
    });

    test('status: "inactive" + left_at → 퇴사로 판정 + 퇴사일 파싱', () {
      final dto = StaffDto.fromJson({
        'uid': 't1',
        'name': '정혜린',
        'status': 'inactive',
        'left_at': '2026-08-22T09:00:00Z',
      });

      expect(dto.isInactive, isTrue);
      expect(dto.leftOn?.year, 2026);
      expect(dto.leftOn?.month, 8);
    });

    test('inactive + 마스킹된 빈 profile — 이름은 남고 소개만 비는 게 정상 응답', () {
      // 계약 v2.0: role=member 응답은 inactive 스태프의 profile을 빈 객체로 마스킹한다.
      // 즉 "퇴사 + 빈 프로필"은 로드 실패가 아니다(프로필 시트 안내 분기의 근거).
      final dto = StaffDto.fromJson({
        'uid': 't1',
        'name': '정혜린',
        'status': 'inactive',
        'profile': <String, dynamic>{},
      });

      expect(dto.name, '정혜린');
      expect(dto.isInactive, isTrue);
      expect(dto.profile.isEmpty, isTrue);
    });

    test('left_at이 깨진 문자열이어도 예외 없이 null(표기만 생략)', () {
      final dto = StaffDto.fromJson({
        'uid': 't1',
        'name': '정혜린',
        'status': 'inactive',
        'left_at': 'not-a-date',
      });

      expect(dto.isInactive, isTrue);
      expect(dto.leftOn, isNull);
    });
  });

  // offdays는 **회원 응답에도 그대로 온다** — ListStaff는 role=member에게 payout만
  // 비우고(그리고 퇴사자 profile만 마스킹하고) 휴무일은 손대지 않는다. 예전 주석은
  // "payout/offdays는 원장·트레이너 전용"이라며 파싱조차 하지 않았고, 그래서 서버가
  // 400("담당 코치의 휴무일이에요")으로 거부할 슬롯이 앱에선 "예약 가능"으로 보였다.
  group('StaffDto.fromJson — offdays (예약 사전 판정의 입력)', () {
    test('휴무일 목록을 그대로 파싱한다', () {
      final dto = StaffDto.fromJson({
        'uid': 't1',
        'name': '정혜린',
        'offdays': ['2026-08-14', '2026-08-15'],
      });

      expect(dto.offdays, ['2026-08-14', '2026-08-15']);
    });

    test('키 누락 → 빈 목록(구버전 서버 호환 — 모른다고 예약을 막지는 않는다)', () {
      final dto = StaffDto.fromJson({'uid': 't1', 'name': '정혜린'});

      expect(dto.offdays, isEmpty);
    });

    test('offdays: null → 빈 목록(계약은 배열 고정이지만 방어)', () {
      final dto = StaffDto.fromJson({'uid': 't1', 'name': '정혜린', 'offdays': null});

      expect(dto.offdays, isEmpty);
    });

    test('payout이 섞여 와도 무시하고 나머지를 파싱한다(미지정 키 무시 규약)', () {
      final dto = StaffDto.fromJson({
        'uid': 't1',
        'name': '정혜린',
        'payout': {'type': 'percent', 'value': 40},
        'offdays': ['2026-09-01'],
      });

      expect(dto.offdays, ['2026-09-01']);
    });
  });
}
