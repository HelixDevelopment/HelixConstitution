package selfcheck

import (
	"strings"
	"testing"
)

// TestSelfcheckGreen asserts the golden fixtures all return their expected
// verdicts — this is the §11.4.107(10) anti-bluff proof that the validator
// itself cannot bluff.
func TestSelfcheckGreen(t *testing.T) {
	ok, out := Run()
	if !ok {
		t.Fatalf("selfcheck must be GREEN; output:\n%s", out)
	}
	if !strings.Contains(out, "selfcheck PASS") {
		t.Fatalf("missing PASS banner:\n%s", out)
	}
}

// TestSelfcheckEachFixtureExtractable proves every embedded fixture extracts +
// runs (catches a missing/renamed golden fixture).
func TestSelfcheckEachFixtureExtractable(t *testing.T) {
	for _, fx := range fixtures {
		pass, detail := runOne(fx)
		if !pass {
			t.Errorf("fixture %q failed: %s", fx.dir, detail)
		}
	}
}
