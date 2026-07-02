// prefix_test.go — anti-bluff coverage for the §11.4.151/§11.4.29 release-prefix
// derivation. These are REAL, falsifiable assertions: if deriveKeyPrefix or the
// env-first resolution regresses, they fail.
package main

import "testing"

// TestDeriveKeyPrefix pins the release-prefix -> 3-uppercase-letter KEY mapping
// the canonical heading (parse.go issueHeadingRe: ^## [A-Z]{3}-…) requires.
func TestDeriveKeyPrefix(t *testing.T) {
	for in, want := range map[string]string{
		"atmosphere":  "ATM",
		"helix_code":  "HEL",
		"code_server": "COD",
		"bob":         "BOB",
		"x":           "XXX",
		"ab":          "ABX",
		"":            "WIT", // no letters -> neutral last-resort key
		"wit":         "WIT",
	} {
		if got := deriveKeyPrefix(in); got != want {
			t.Errorf("deriveKeyPrefix(%q)=%q want %q", in, got, want)
		}
	}
}

// TestResolveReleasePrefix_EnvWins proves HELIX_RELEASE_PREFIX takes precedence
// and flows through to the derived default KEY.
func TestResolveReleasePrefix_EnvWins(t *testing.T) {
	t.Setenv("HELIX_RELEASE_PREFIX", "myproject")
	if got := defaultKeyPrefix(); got != "MYP" {
		t.Fatalf("defaultKeyPrefix()=%q want MYP", got)
	}
}

// TestSnakeCase proves the §11.4.29 lowercased snake_case normalisation used for
// the dir-name fallback.
func TestSnakeCase(t *testing.T) {
	for in, want := range map[string]string{
		"HelixCode":      "helix_code",
		"code-server":    "code_server",
		"Workable Items": "workable_items",
		"already_snake":  "already_snake",
		"--leading--":    "leading",
	} {
		if got := snakeCase(in); got != want {
			t.Errorf("snakeCase(%q)=%q want %q", in, got, want)
		}
	}
}
