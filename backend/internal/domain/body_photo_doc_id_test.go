package domain

import (
	"strings"
	"testing"
)

// BodyPhotoDocID는 **저장된 데이터의 계약**이다(P76) — 문서 ID가 Firestore에 그대로 남고, 메타 POST 재시도는 같은
// 경로 → 같은 ID에 기대어 하나로 모인다. 공식이 바뀌면 배포 전후로 걸친 재시도가 레코드를 둘 만들고, 이미 저장된
// ID와 새 ID가 갈린다 — 그래서 값을 리터럴로 못박는다(hwCheckDocID의 TestHwCheckSortKeyIsTheFirestoreDocID와 같은 부류).
func TestBodyPhotoDocIDIsStable(t *testing.T) {
	path := "members/m1/body/20261016-stand-front-1760000000000.jpg"
	// printf '%s' path | shasum -a 256 | cut -c1-32
	const want = "bp_f747bf16c561a0bd8e71f428287faa74"
	if got := BodyPhotoDocID(path); got != want {
		t.Fatalf("BodyPhotoDocID = %q, want %q — 공식이 바뀌면 저장된 ID와 갈린다", got, want)
	}
	if BodyPhotoDocID(path) != BodyPhotoDocID(path) {
		t.Error("같은 경로가 다른 ID를 냈다")
	}
	if BodyPhotoDocID(path) == BodyPhotoDocID(path+"x") {
		t.Error("다른 경로가 같은 ID를 냈다")
	}
	if id := BodyPhotoDocID(path); strings.ContainsAny(id, "/.") || len(id) != 3+32 {
		t.Errorf("문서 ID로 못 쓰는 모양: %q", id)
	}
}
