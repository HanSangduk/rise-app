---
id: P05
title: 트레이너 프로필(사진·이력) — 리서치·구현
status: 완료
domain: cross
created: 2026-08-22
completed: 2026-08-22
---

# P05 — 트레이너 프로필(사진·이력)

## 목표

회원이 트레이너의 사진·이력(직함·경력·자격증·수상·전문분야·소개)을 보고 상담·재등록·수업 선택에
참고할 수 있게 한다. 어드민에 프로필 편집 UI 추가. 자문자답 0까지 반복 검수.

## 결정 사항 (리서치·자문자답 — work_log 참조: P05 리서치 보고)

- **Staff.profile 인라인 확장**(별도 엔티티 아님) — GET /v1/staff가 이미 전 역할 사용 중이라
  앱 조회 신규 API 0개. 설계03 §9 "코치 프로필" 원설계 복원.
- **photo_url 외부 URL(v1)** + 이니셜 아바타 폴백(Staff.color 배경). 업로드는 Storage 트랙 후속 —
  도입 시 서버가 photo_url을 채우므로 클라이언트 계약 불변. javascript: 스킴 차단.
- **PUT /v1/staff/{uid}/profile** — owner 또는 본인 trainer(offdays 동일 권한), 통 교체 시맨틱.
- 필드: photo_url·title·career_years·specialties[]·certifications[]·awards[]·bio (시장 표준 —
  운동닥터·다짐·포인티 실존 확인 기반).
- **제외**: 리뷰/평점(단일 센터 표본 부족·갈등 리스크 — 동종 CRM 포인티도 없음), 가격(Pass가 자리),
  SNS(근거 부족), 업로드(후속), 승인 큐(owner 상시 정정 가능), 별도 어드민 페이지(Settings 확장으로 충분).
- 앱 접점: 예약 탭 코치 표시 지점 탭→프로필 시트(핵심 — 복수 패스 선택·재등록 상담 참고) +
  온보딩 담당 코치 한 줄 소개. 홈 카드 확장은 선택 가치 없어 제외.

## 진행 단계

- [x] 1. 리서치(시장 실존 서비스 필드 도출 + 자문자답 8문) — 설계 확정
- [x] 2. backend v1.6: StaffProfile 도메인(+검증/Normalize) · PUT profile · ListStaff 포함 ·
      DEV_SEED 3명 프로필 · 테스트(스코프 403/검증 400/null 금지/member 공개+payout 마스킹 유지)
      — go test 전부 그린 · 계약 v1.6 절
- [x] 3. admin 완료: 직원 표 아바타·직함·미등록 뱃지 + ProfileModal(URL 미리보기·칩 에디터
      IME 가드·500자 카운터·통 교체) — build exit 0 + 실연동(400 4종·권한 3종·빈 프로필 지우기).
      검증 중 백엔드 ErrInvalidProfile 400 매핑 누락(500으로 샘) 발견·1줄 수정(go test 그린)
- [x] 4. app 완료: StaffDto profile(+테스트 4) · TrainerAvatar(이니셜 폴백) · ProfileSheet ·
      진입점 3곳(내 코치 칩·전체 보기 태그·온보딩 카드) + 확정 시트 아바타
- [x] 5. 통합 검수 + 보완: 프로필 발견성("코치 소개" 버튼+칩 아바타) · staffMap 실패 비고착 ·
      폴백 문구 구분 · 히트 영역 · photo_url 대소문자 · penalty_rate 포인터(0%/레거시 구분) ·
      ErrInvalidProfile 400 매핑 — 최종 매트릭스 그린(P0405_FINAL=0)

## 변경 파일

- backend: domain/staff.go(+StaffProfile) · api/{service,handlers_staff,router}.go · store/seed.go ·
  service_test.go(+1 종합) · docs/API계약_v1.md v1.6 절

## 검증

- backend: go build/vet/test 그린(프로필 스코프·검증·직렬화 규약 테스트 포함)

## 후속 작업

- 사진 실업로드(Firebase Storage 트랙 — POST /v1/staff/{uid}/photo가 photo_url을 채우는 방식,
  클라이언트 계약 불변)
- 트레이너 본인 편집 UI(백엔드 허용 완료 — 트레이너 모바일 트랙)
- 후보 풀(설계 결정 필요): 프로필 링크 공유(포인티 방식 영업 자산화)

## 참조

- work_log/P04(병행 트랙) · 설계03 §9
