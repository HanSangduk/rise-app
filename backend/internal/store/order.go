package store

// 목록 정렬 규약 — Memory와 Firestore가 **같은 순서**를 돌려주게 하는 단일 규칙.
//
// Firestore는 orderBy가 없는 쿼리를 문서 ID(__name__) 오름차순으로 돌려준다(equality Where가
// 붙어도 마찬가지다 — 범위 필터가 없으면 암묵 정렬은 __name__ 하나뿐이다). 반면 Memory는 맵을
// 순회하므로 **호출마다 순서가 달라진다**. 정렬을 넣지 않은 목록은 그래서 "로컬에선 새로고침마다
// 뒤바뀌고 프로덕션에선 고정"이라는, 개발 중엔 재현조차 어려운 차이를 만든다 — 회원 앱의 기본
// 패스 선택(home_repository_impl.dart의 _defaultPass)이 목록의 첫 active 패스를 집으므로
// 순서가 곧 화면이다.
//
// 그래서 두 구현이 이 파일의 비교자 하나를 공유한다(normalizePhone·betterPhoneMatch와 같은
// 이유·같은 자리 — 규칙이 갈리면 로컬에선 되고 프로덕션에선 안 되는 버그가 된다).
// Firestore 쪽 정렬은 서버가 이미 주는 순서를 한 번 더 확정하는 것이라 결과를 바꾸지 않는다.
// 그 대신 ① "무엇이 기준인가"가 코드에 남고 ② 에뮬레이터 없이도 Memory로 같은 규칙을 검증할
// 수 있고 ③ 나중에 Where 조합이 바뀌어 서버 순서가 흔들려도 응답은 흔들리지 않는다.

import (
	"sort"

	"github.com/ramsang/rise-backend/internal/domain"
)

// sortByDocID — 문서 ID 오름차순(Firestore 기본 순서와 동일). 두 스토어가 공유하는 유일한
// 목록 정렬자다.
func sortByDocID[T any](rows []T, docID func(T) string) {
	sort.Slice(rows, func(i, j int) bool { return docID(rows[i]) < docID(rows[j]) })
}

// sortPasses — 회원권 목록의 단일 정렬 규칙: **valid_from 오름차순, 동률이면 문서 ID 오름차순**.
//
// 문서 ID 정렬(sortByDocID)을 쓰지 않는 유일한 컬렉션이다. ID 정렬은 두 스토어에서 "같은 규칙"
// 이긴 해도 **같은 순서**가 아니었다: Memory의 ID는 발급 순서를 담은 시퀀스(pass_000001)라
// 결과적으로 발급 순이지만, Firestore의 ID는 무작위 20자라 목록 순서가 사실상 제비뽑기다
// (P13 M1 실측). 회원 앱의 기본 회원권 선택(_defaultPass)은 목록의 첫 active 패스를 집으므로
// **순서가 곧 화면**이고, 재등록으로 패스가 2개인 회원은 새로고침마다 다른 회원권이 기본이 됐다.
//
// 기준을 valid_from으로 잡은 이유: 회원권은 "먼저 시작한 것부터 쓴다"가 실제 소진 순서이고,
// 그 값은 두 스토어에 똑같이 저장돼 있다(문서 ID 체계와 달리 substrate 중립). 오름차순이라
// 진행 중인 회원권이 앞, 선등록한 미래 회원권이 뒤에 온다.
//
// 남은 한계: valid_from이 같은 두 패스는 문서 ID로 갈리므로 두 스토어의 순서가 다를 수 있다.
// 완전히 없애려면 Pass에 created_at을 추가해야 하는데(API 계약 변경) 같은 날 시작하는 회원권
// 두 개는 v1 실사용에 없어 보류한다.
func sortPasses(rows []domain.Pass) {
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].ValidFrom != rows[j].ValidFrom {
			return rows[i].ValidFrom < rows[j].ValidFrom
		}
		return rows[i].ID < rows[j].ID
	})
}

// sortInbody — 인바디 목록의 단일 정렬 규칙: **date 내림차순(최신 먼저), 동률이면 문서 ID
// 오름차순**.
//
// 1차 키는 종전과 같고(앱 차트가 최신 먼저를 전제한다), 여기서 더한 건 **타이브레이커**다.
// v2.9가 같은 회원·같은 날 중복 생성을 409로 막지만 그 이전에 저장된 동일 날짜 2건은 그대로
// 남아 있고, 날짜만으로 정렬하면 그 두 건의 상대 순서가 Memory에선 맵 순회(호출마다 뒤바뀜) ·
// Firestore에선 문서 ID(고정)로 갈린다. 인바디는 앱 기록 탭의 추이선과 "직전 대비 증감"의
// 입력이라 순서가 곧 화면이고, 로컬에서만 흔들리는 값은 재현조차 어렵다(sortPasses와 같은 이유).
func sortInbody(rows []domain.Inbody) {
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Date != rows[j].Date {
			return rows[i].Date > rows[j].Date
		}
		return rows[i].ID < rows[j].ID
	})
}

// ---- 1차 키 + 문서 ID 타이브레이커(P76) ----
//
// 아래 목록들은 1차 키 하나로만 sort.Slice를 돌리고 있었다. 1차 키는 겹칠 수 있다(같은 µs에 만든
// 가입 요청 — 맥의 실시각 해상도는 1µs다, 동명이인, 같은 슬롯의 그룹 예약, 같은 날 찍은 체형사진
// 여러 장, 한 트랜잭션이 같은 시각으로 쓴 원장 두 줄). 그러면 동률의 상대 순서가 Memory에선 맵 순회로
// 호출마다 뒤바뀌고, Firestore에선 불안정 정렬이 정한 임의 순서가 된다 — sortPasses·sortInbody가
// 막은 바로 그 부류다. 실측: `TestMeJoinRequestFollowsSelectedCenter`가 300회 중 72회 실패했다
// (/v1/me의 join_request는 목록의 **첫 항목 = 현재 상태**라 순서가 곧 답이다).
//
// 동률의 방향: "최신 먼저"인 시각 목록(가입 요청·원장)은 **ID 내림차순** — Memory의 ID는 발급 순
// 시퀀스라 나중에 만든 것이 앞에 와서 1차 키의 뜻과 맞는다. 날짜·이름·슬롯 목록은 sortInbody와
// 같은 **ID 오름차순**.

// sortJoinRequestsNewest — 가입 요청: created_at 내림차순, 동률이면 문서 ID 내림차순.
func sortJoinRequestsNewest(rows []JoinRequest) {
	sort.Slice(rows, func(i, j int) bool {
		if !rows[i].CreatedAt.Equal(rows[j].CreatedAt) {
			return rows[i].CreatedAt.After(rows[j].CreatedAt)
		}
		return rows[i].ID > rows[j].ID
	})
}

// sortLedgerNewest — 원장: at 내림차순, 동률이면 문서 ID 내림차순.
func sortLedgerNewest(rows []domain.Ledger) {
	sort.Slice(rows, func(i, j int) bool {
		if !rows[i].At.Equal(rows[j].At) {
			return rows[i].At.After(rows[j].At)
		}
		return rows[i].ID > rows[j].ID
	})
}

// sortMembersByName — 회원: 이름 오름차순, 동명이인은 문서 ID 오름차순.
func sortMembersByName(rows []domain.Member) {
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Name != rows[j].Name {
			return rows[i].Name < rows[j].Name
		}
		return rows[i].ID < rows[j].ID
	})
}

// sortStaffByName — 스태프: 이름 오름차순, 동명이인은 UID(문서 ID) 오름차순.
func sortStaffByName(rows []domain.Staff) {
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Name != rows[j].Name {
			return rows[i].Name < rows[j].Name
		}
		return rows[i].UID < rows[j].UID
	})
}

// sortBookingsBySlot — 예약: slot_key 오름차순, 같은 슬롯(그룹 수업)이면 문서 ID 오름차순.
func sortBookingsBySlot(rows []domain.Booking) {
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].SlotKey != rows[j].SlotKey {
			return rows[i].SlotKey < rows[j].SlotKey
		}
		return rows[i].ID < rows[j].ID
	})
}

// sortBodyPhotos — 체형사진: date 내림차순, 같은 날이면 문서 ID 오름차순(sortInbody와 같은 규칙).
func sortBodyPhotos(rows []domain.BodyPhoto) {
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Date != rows[j].Date {
			return rows[i].Date > rows[j].Date
		}
		return rows[i].ID < rows[j].ID
	})
}

// sortWorkoutLogs — 수업 기록: date 내림차순, 같은 날이면 문서 ID 오름차순(sortInbody와 같은 규칙).
func sortWorkoutLogs(rows []domain.WorkoutLog) {
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Date != rows[j].Date {
			return rows[i].Date > rows[j].Date
		}
		return rows[i].ID < rows[j].ID
	})
}

// 컬렉션별 "문서 ID" 추출자. 대부분은 엔티티 ID가 곧 문서 ID다 — Firestore의 Create* 구현이
// ref.ID를 그대로 엔티티 ID에 넣는다(그래서 ID 오름차순 = 문서 ID 오름차순).
// (passes는 위 sortPasses가 담당한다 — 문서 ID로 정렬하지 않는 유일한 컬렉션)
func recurringDocID(r domain.Recurring) string { return r.ID }
func homeworkDocID(h domain.Homework) string   { return h.ID }
func paymentDocID(p domain.Payment) string     { return p.ID }

// hwCheckDocIDOf — HwCheck만 엔티티 ID 필드가 없고 문서 ID가 합성 키다(회원+홈워크+날짜,
// 하루 1건 upsert). 정렬 키도 그 합성 ID여야 Firestore와 같은 순서가 된다 — Memory의 맵 키
// (구분자 "/")로 정렬하면 구분자 바이트가 달라 순서가 갈릴 수 있다.
func hwCheckDocIDOf(c domain.HwCheck) string { return hwCheckDocID(c.MemberID, c.HwID, c.Date) }

// hwCheckDocID — hwChecks 컬렉션의 문서 ID 규칙. Firestore의 저장 키이자 두 스토어의 정렬 키다.
func hwCheckDocID(memberID, hwID, date string) string {
	return docKey(memberID) + "_" + docKey(hwID) + "_" + docKey(date)
}

// docKey — 문서 ID로 못 쓰는 문자를 치환.
func docKey(s string) string {
	out := make([]rune, 0, len(s))
	for _, r := range s {
		switch r {
		case '/', '\\', '.', '#', '$', '[', ']':
			out = append(out, '_')
		default:
			out = append(out, r)
		}
	}
	return string(out)
}
