package domain

import (
	"testing"
	"time"
)

// 체형사진 소프트 삭제(v2.13).
//
// 잘못 눌러 지우면 되돌릴 방법이 없다 — 그날의 몸은 다시 못 찍는다. 그래서 즉시
// 파기하지 않고 유예를 둔다. 다만 회원·코치 화면에서는 즉시 사라져야 "지웠다"는
// 약속이 지켜진다.

func ptr(t time.Time) *time.Time { return &t }

func TestBodyPhotoSoftDelete(t *testing.T) {
	now := time.Date(2026, 8, 27, 12, 0, 0, 0, time.UTC)

	t.Run("삭제 표시가 없으면 살아 있다", func(t *testing.T) {
		var b BodyPhoto
		if b.IsDeleted() || b.PurgeDue(now) {
			t.Fatal("살아 있는 사진이 삭제로 판정됐다")
		}
		if b.DaysUntilPurge(now) != nil {
			t.Fatal("살아 있는 사진에 파기 예정일이 붙었다")
		}
	})

	t.Run("삭제 직후에는 숨기되 파기하지 않는다", func(t *testing.T) {
		b := BodyPhoto{DeletedAt: ptr(now)}
		if !b.IsDeleted() {
			t.Fatal("삭제한 사진이 목록에 남는다")
		}
		if b.PurgeDue(now) {
			t.Fatal("유예 없이 즉시 파기됐다 — 오조작을 되돌릴 수 없다")
		}
		if d := b.DaysUntilPurge(now); d == nil || *d != 30 {
			t.Fatalf("남은 일수 = %v, want 30", d)
		}
	})

	t.Run("경계 — 30일째는 아직, 넘겨야 파기", func(t *testing.T) {
		// 회원에게 "30일 뒤"라고 안내하는 값과 실제 파기 시점이 하루라도 어긋나면 안 된다.
		exactly := BodyPhoto{DeletedAt: ptr(now.Add(-BodyPhotoPurgeAfter))}
		if exactly.PurgeDue(now) {
			t.Fatal("30일째에 파기됐다 — 안내보다 하루 빠르다")
		}
		past := BodyPhoto{DeletedAt: ptr(now.Add(-BodyPhotoPurgeAfter - time.Second))}
		if !past.PurgeDue(now) {
			t.Fatal("30일을 넘겼는데 파기되지 않는다")
		}
	})

	t.Run("남은 일수는 음수가 되지 않는다", func(t *testing.T) {
		// 스케줄러 없이 조회 시점에 훑으므로 한참 지난 뒤에 처음 보일 수 있다.
		b := BodyPhoto{DeletedAt: ptr(now.Add(-100 * 24 * time.Hour))}
		if d := b.DaysUntilPurge(now); d == nil || *d != 0 {
			t.Fatalf("남은 일수 = %v, want 0", d)
		}
	})

	t.Run("유예값이 방침 문구와 같다", func(t *testing.T) {
		// 개인정보처리방침이 "30일"이라 적었다 — 이 상수를 바꾸면 문서도 바꿔야 한다.
		if BodyPhotoPurgeAfter != 30*24*time.Hour {
			t.Fatalf("유예 = %v, 방침 문구는 30일", BodyPhotoPurgeAfter)
		}
	})
}
