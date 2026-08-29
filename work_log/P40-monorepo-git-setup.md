---
id: P40
title: 모노레포 git 전환 (HanSangduk/rise-app)
status: 진행 중
domain: cross
created: 2026-08-29
completed:
---

# P40 — 모노레포 git 전환 (HanSangduk/rise-app)

## 목표

ptdesk 루트를 하나의 git 저장소로 만들어 https://github.com/HanSangduk/rise-app.git 에 올린다. admin(React)·app(Flutter)·backend(Go)를 저장소 분리 없이 모노레포로 관리.

## 결정 사항

- **모노레포 채택**. 근거: (1) 세 계층이 firebase.json·firestore.rules·storage.rules·deploy-hosting.sh 하나를 공유 — 쪼개면 rules 소유가 애매해지고 스키마 변경을 원자 커밋으로 못 묶음. (2) 1인 개발이라 repo 분리의 이점(권한 분리·독립 CI)이 현재 없음. (3) 설계 문서·work_log·docs가 루트에 있음. 팀 확장/외주 시점에 git subtree split으로 분리 가능.
- **Firebase 클라이언트 설정 파일은 커밋** — app/ios/Runner/GoogleService-Info.plist, app/android/app/google-services.json은 클라이언트 식별자(비밀 아님)이고 빌드에 필요. 비공개 repo 전제.
- git init·remote add·첫 push는 Claude git 정책(금지 목록)상 사용자가 직접 실행.

## 진행 단계

- [x] 커밋 전 안전성 스캔: .env류·serviceAccount·keystore·local.properties 전수 확인 — 전부 sub .gitignore로 커버됨
- [x] 루트 .gitignore에 `.claude/scheduled_tasks.lock` 추가
- [ ] 사용자: git init → remote add → 첫 커밋 → push
- [ ] push 후 GitHub에서 파일 목록 눈검수 (자격증명·빌드 산출물 유입 여부)

## 변경 파일

- `.gitignore` — 도구 산출물에 `.claude/scheduled_tasks.lock` 추가

## 검증

- `find`로 자격증명 후보 전수 스캔: `.env.example` 2건(커밋 대상, 정상), local.properties·key.properties·keystore는 app/android/.gitignore가 커버, ios `Flutter/ephemeral/`은 app/ios/.gitignore가 커버, firestore-debug.log는 backend/.gitignore가 커버 확인.
- 대용량 확인: admin/node_modules 308M(ignored), app/build 5.3G(ignored), design/ 112K(커밋 대상).

## 후속 작업

- 첫 push 후 저장소 Settings에서 private 여부 확인 (GoogleService-Info.plist 커밋 전제가 비공개 repo).
- 브랜치 전략 결정(main 단일 vs main+feature) — 이후 Claude가 feature 브랜치에서 커밋 대행 가능해짐.

## 참조

- 루트 `.gitignore`, `admin/.gitignore`, `app/.gitignore`, `app/android/.gitignore`, `app/ios/.gitignore`, `backend/.gitignore`
