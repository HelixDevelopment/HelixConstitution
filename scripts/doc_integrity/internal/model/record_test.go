package model

import (
	"testing"
	"time"
)

func TestHasDatesBothPresent(t *testing.T) {
	now := time.Now()
	r := Record{Start: &now, Deadline: &now}
	if !r.HasDates() {
		t.Fatal("HasDates should be true when both present")
	}
}

func TestHasDatesOneMissing(t *testing.T) {
	now := time.Now()
	r := Record{Start: &now}
	if r.HasDates() {
		t.Fatal("HasDates should be false when deadline missing")
	}
}

func TestHasDatesBothNil(t *testing.T) {
	r := Record{}
	if r.HasDates() {
		t.Fatal("HasDates should be false when both nil")
	}
}

func TestHasAnyDate(t *testing.T) {
	now := time.Now()
	if !(Record{Start: &now}).HasAnyDate() {
		t.Fatal("HasAnyDate true with start only")
	}
	if !(Record{Deadline: &now}).HasAnyDate() {
		t.Fatal("HasAnyDate true with deadline only")
	}
	if (Record{}).HasAnyDate() {
		t.Fatal("HasAnyDate false with neither")
	}
}
