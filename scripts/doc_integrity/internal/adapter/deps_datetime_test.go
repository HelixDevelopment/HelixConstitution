package adapter

import (
	"reflect"
	"testing"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/normalize"
)

// TestSplitDepsDateHandling is the ATM-687 unit guard: a date value in the
// dependencies column (the excelize-rendered "3/6/2001" of V9 cell E156) must
// NOT fragment into bogus "3"/"6"/"2001" dependency-ref candidates, while a
// genuine dotted item-ref like "5.0.1" and slash-separated real refs survive
// intact (§11.4.146 extend-to-all-cases). RED-on-broken (revert splitDeps) →
// "3/6/2001" produces ["3","6","2001"] → this fails; GREEN post-fix → [].
func TestSplitDepsDateHandling(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want []string
	}{
		{"whole-cell date dropped", "3/6/2001", nil},
		{"date with surrounding space dropped", "  3/6/2001  ", nil},
		{"dotted item-ref survives", "5.0.1", []string{"5.0.1"}},
		{"date + genuine orphan keeps only the orphan", "3/6/2001, 9.9.9", []string{"9.9.9"}},
		{"slash-separated real refs survive", "ATM-1/ATM-2", []string{"ATM-1", "ATM-2"}},
		{"comma-separated real refs survive", "ATM-100, ATM-200", []string{"ATM-100", "ATM-200"}},
		{"ISO date dropped", "2027-05-03", nil},
		{"empty is empty", "", nil},
		{"none sentinel dropped", "none", nil},
		{"dash sentinel dropped", "-", nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := splitDeps(c.in)
			if !reflect.DeepEqual(got, c.want) {
				t.Fatalf("splitDeps(%q) = %#v, want %#v", c.in, got, c.want)
			}
		})
	}
}

// TestIsDateLike locks the date/datetime discriminator: dates and datetimes are
// date-like (so they get dropped from deps); dotted item-refs and tickets are
// NOT date-like (so they still tokenize and still get flagged by INTEG-01).
func TestIsDateLike(t *testing.T) {
	dateLike := []string{
		"3/6/2001",
		"2001-03-06",
		"2027-05-03",
		"2026/08/10",
		"06.03.2001",
		"2027-05-03T12:34:56",
		"2027-05-03 12:34:56",
	}
	notDateLike := []string{
		"5.0.1",
		"9.9.9",
		"ATM-599",
		"ATM-1",
		"",
		"none",
	}
	for _, s := range dateLike {
		if !normalize.IsDateLike(s) {
			t.Errorf("IsDateLike(%q) = false, want true", s)
		}
	}
	for _, s := range notDateLike {
		if normalize.IsDateLike(s) {
			t.Errorf("IsDateLike(%q) = true, want false", s)
		}
	}
}
