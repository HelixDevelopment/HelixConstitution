package normalize

import "testing"

func TestSubjectDeterministic(t *testing.T) {
	in := "  NanoKVM: Screen-Display (touch)!  "
	first := Subject(in)
	for i := 0; i < 100; i++ {
		if Subject(in) != first {
			t.Fatal("Subject must be deterministic across N runs (§11.4.50)")
		}
	}
	if first != "nanokvm screen display touch" {
		t.Fatalf("unexpected normalisation: %q", first)
	}
}

func TestSubjectUnicodeRU(t *testing.T) {
	if Subject("Интеграция NanoKVM") != "интеграция nanokvm" {
		t.Fatalf("RU normalisation wrong: %q", Subject("Интеграция NanoKVM"))
	}
}

func TestDateParsing(t *testing.T) {
	if Date("2026-09-17") == nil {
		t.Fatal("ISO date must parse")
	}
	if Date("") != nil {
		t.Fatal("empty date must be nil")
	}
	if Date("GATED") != nil {
		t.Fatal("non-date must be nil, never guessed (§11.4.6)")
	}
}

func TestScopeEmptyAndNonEmpty(t *testing.T) {
	if Scope("") != "" {
		t.Fatal("Scope of empty must stay empty (honest empty, §11.4.6)")
	}
	if Scope("  NanoKVM: Touch  ") != "nanokvm touch" {
		t.Fatalf("Scope normalisation wrong: %q", Scope("  NanoKVM: Touch  "))
	}
}

func TestIsDateLike(t *testing.T) {
	// Valid dates
	for _, s := range []string{"2026-09-17", "2026/09/17", "17.09.2026", "09/17/2026", "2026-9-7"} {
		if !IsDateLike(s) {
			t.Fatalf("IsDateLike(%q) should be true", s)
		}
	}
	// Valid datetimes
	for _, s := range []string{"2026-09-17T12:00:00", "2026-09-17 12:00:00", "3/6/2001"} {
		if !IsDateLike(s) {
			t.Fatalf("IsDateLike(%q) should be true (datetime)", s)
		}
	}
	// NOT date-like
	for _, s := range []string{"", "GATED", "ATM-599", "5.0.1", "not a date"} {
		if IsDateLike(s) {
			t.Fatalf("IsDateLike(%q) should be false", s)
		}
	}
}

func TestSimilarity(t *testing.T) {
	if Similarity("nanokvm integration", "nanokvm integration") != 1.0 {
		t.Fatal("identical strings similarity must be 1.0")
	}
	if Similarity("nanokvm integration", "nanokvm touch") >= 0.9 {
		t.Fatal("distinct-scope subjects must be below the 0.9 fuzzy threshold")
	}
	if Similarity("", "x") != 0.0 {
		t.Fatal("empty-vs-nonempty similarity must be 0.0")
	}
}
