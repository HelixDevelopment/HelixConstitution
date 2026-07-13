// Package runner loads a checkset's sources through the adapters and runs the
// five check families, producing a report.Result. An unavailable source is an
// honest SKIP (§11.4.3), never a fake PASS.
package runner

import (
	"errors"
	"fmt"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/adapter"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/check"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/report"
)

// Run loads the checkset at cfgPath (paths resolved against repoRoot) and
// returns a finalized Result. A config/parse error returns a non-nil error so
// the caller can exit 2; source-load unavailability is folded into the Result as
// a SKIP, never an error.
func Run(cfgPath, repoRoot string) (*report.Result, error) {
	cfg, err := config.Load(cfgPath)
	if err != nil {
		return nil, err
	}

	res := &report.Result{
		Checkset:   cfgPath,
		SourceRows: map[string]int{},
	}
	var sources []check.SourceData
	for _, src := range cfg.Sources {
		lr, err := adapter.Load(src, repoRoot)
		if err != nil {
			if errors.Is(err, adapter.ErrSourceUnavailable) {
				res.Skips = append(res.Skips, report.Skip{SourceID: src.ID, Reason: err.Error()})
				continue
			}
			return nil, fmt.Errorf("source %q: %w", src.ID, err)
		}
		res.SourceRows[src.ID] = len(lr.Records)
		sources = append(sources, check.SourceData{
			Src:     src,
			Records: lr.Records,
			Present: lr.PresentColumns,
		})
	}

	ds := check.NewDataset(cfg, sources)
	res.Findings = check.RunAll(ds)
	res.Finalize()
	return res, nil
}
