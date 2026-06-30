// prefix.go — §11.4.151 / §11.4.29 release-prefix resolution. The workable-items
// tracker is fully DECOUPLED from any single consuming project: the ticket-id
// KEY/PREFIX is DERIVED, never hardcoded to a real project name.
package main

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// neutralKeyFallback is the project-agnostic last-resort 3-letter KEY, used ONLY
// when no release prefix resolves AND the resolved name carries no letters. It is
// generic ("workable-items tracker") — NOT a real project key.
const neutralKeyFallback = "WIT"

// resolveReleasePrefix derives the lowercase release prefix per §11.4.151:
//
//	(1) HELIX_RELEASE_PREFIX from the environment, when non-empty;
//	(2) else HELIX_RELEASE_PREFIX from a `.env` file at/above the CWD;
//	(3) else the lowercased snake_case of the project root directory name
//	    (§11.4.29).
func resolveReleasePrefix() string {
	if v := strings.TrimSpace(os.Getenv("HELIX_RELEASE_PREFIX")); v != "" {
		return v
	}
	if v := dotenvValue("HELIX_RELEASE_PREFIX"); v != "" {
		return v
	}
	return snakeCase(projectRootName())
}

// defaultKeyPrefix is the resolved, derived default for `add --prefix`.
func defaultKeyPrefix() string { return deriveKeyPrefix(resolveReleasePrefix()) }

// deriveKeyPrefix converts a release prefix into the 3-uppercase-letter KEY the
// canonical tracker heading requires (parse.go issueHeadingRe: ^## [A-Z]{3}-…).
// It keeps only ASCII letters, uppercases them, and takes the first three —
// "atmosphere"->"ATM", "helix_code"->"HEL", "bob"->"BOB". <3 letters are
// right-padded with 'X'; none at all falls back to the neutral key.
func deriveKeyPrefix(release string) string {
	var b strings.Builder
	for _, r := range release {
		switch {
		case r >= 'a' && r <= 'z':
			b.WriteRune(r - 32)
		case r >= 'A' && r <= 'Z':
			b.WriteRune(r)
		}
		if b.Len() == 3 {
			break
		}
	}
	s := b.String()
	if s == "" {
		return neutralKeyFallback
	}
	for len(s) < 3 {
		s += "X"
	}
	return s
}

// projectRootName returns the base name of the consuming project's root — the
// OUTERMOST ancestor of the CWD that contains a `.git` entry; the CWD itself when
// none is found.
func projectRootName() string {
	wd, err := os.Getwd()
	if err != nil || wd == "" {
		return ""
	}
	root, dir := wd, wd
	for {
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			root = dir // keep climbing: outermost .git wins
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return filepath.Base(root)
}

// dotenvValue scans `.env` files from the CWD upward for `key=value` (tolerating
// a leading `export `, surrounding quotes and `#` comments) and returns the first
// match, or "".
func dotenvValue(key string) string {
	dir, err := os.Getwd()
	if err != nil {
		return ""
	}
	for {
		if v, ok := readDotenvKey(filepath.Join(dir, ".env"), key); ok {
			return v
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

func readDotenvKey(path, key string) (string, bool) {
	f, err := os.Open(path)
	if err != nil {
		return "", false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		ln := strings.TrimSpace(sc.Text())
		ln = strings.TrimPrefix(ln, "export ")
		if ln == "" || strings.HasPrefix(ln, "#") {
			continue
		}
		eq := strings.IndexByte(ln, '=')
		if eq < 0 || strings.TrimSpace(ln[:eq]) != key {
			continue
		}
		return strings.Trim(strings.TrimSpace(ln[eq+1:]), `"'`), true
	}
	return "", false
}

// snakeCase lowercases s and turns runs of non-alphanumeric characters into a
// single underscore, inserting an underscore at lower->upper camelCase
// boundaries ("HelixCode"->"helix_code"). §11.4.29.
func snakeCase(s string) string {
	var b strings.Builder
	prevLower, lastUnderscore := false, true // suppress a leading underscore
	for _, r := range s {
		switch {
		case r >= 'A' && r <= 'Z':
			if prevLower {
				b.WriteByte('_')
			}
			b.WriteRune(r + 32)
			prevLower, lastUnderscore = false, false
		case (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
			b.WriteRune(r)
			prevLower, lastUnderscore = r >= 'a' && r <= 'z', false
		default:
			if !lastUnderscore {
				b.WriteByte('_')
				lastUnderscore = true
			}
			prevLower = false
		}
	}
	return strings.Trim(b.String(), "_")
}
