package main

// config.go -- the llm-alias-health config schema (PART D of
// docs/research/llmsverifier_incorporation_20260707/ANALYSIS_AND_PLAN.md,
// ATMOSphere-Android-15 repo). Project-agnostic (§11.4.28(B)): no
// ATMOSphere alias id, path, or credential value is hardcoded here --
// every alias's specifics are supplied by the consumer's own config file
// + env vars.

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// AliasKind is the closed set of alias env-matrix shapes the LLMsVerifier
// claude-alias-probe bridge understands (mirrors
// providers.ClaudeCodeAliasKind in the LLMsVerifier submodule, kept as a
// plain string here so this util never imports that module -- §11.4.28(C)
// exec-decoupling).
type AliasKind string

const (
	KindNative         AliasKind = "native"
	KindProviderNative AliasKind = "provider-native"
	KindProviderRouter AliasKind = "provider-router"
)

var validKinds = map[AliasKind]bool{
	KindNative:         true,
	KindProviderNative: true,
	KindProviderRouter: true,
}

// AliasConfig names one alias's env matrix, exactly as passed to the
// LLMsVerifier claude-alias-probe bridge's CLI flags. Secrets are NEVER
// stored here -- only the NAME of the env var that holds one
// (§11.4.10 credentials-handling).
type AliasConfig struct {
	Alias        string    `yaml:"alias"`
	Kind         AliasKind `yaml:"kind"`
	ConfigDir    string    `yaml:"config_dir,omitempty"`
	BaseURL      string    `yaml:"base_url,omitempty"`
	Model        string    `yaml:"model,omitempty"`
	AuthTokenEnv string    `yaml:"auth_token_env,omitempty"`
	APIKeyEnv    string    `yaml:"api_key_env,omitempty"`
}

// Config is the top-level llm-alias-health config document.
type Config struct {
	// LLMsVerifierBin is the path to the LLMsVerifier claude-alias-probe
	// bridge binary. INJECTED, never hardcoded (§11.4.28(B)/(C)) -- this
	// util execs it, it never imports LLMsVerifier as a Go dependency.
	LLMsVerifierBin string `yaml:"llmsverifier_bin"`
	Aliases         []AliasConfig `yaml:"aliases"`
	// TimeoutSeconds is the per-alias probe timeout passed through to the
	// bridge's own --timeout flag. Defaults to 60 when <= 0.
	TimeoutSeconds int `yaml:"timeout_seconds"`
	// SentinelPrefix is prepended to a per-run random suffix to build the
	// deterministic round-trip token each probe asks the model to echo
	// back. Defaults to a generic, non-consumer-specific prefix.
	SentinelPrefix string `yaml:"sentinel_prefix"`
}

const defaultSentinelPrefix = "LLM_ALIAS_HEALTH_"
const defaultTimeoutSeconds = 60

// loadConfig reads + validates the YAML config at path. Every validation
// failure is a config error (never silently ignored/defaulted away),
// mirroring the LLMsVerifier bridge's own --sentinel/--kind validation
// discipline (§11.4.6 no-guessing).
func loadConfig(path string) (Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config %q: %w", path, err)
	}
	return parseConfig(b)
}

// parseConfig is the pure (no I/O) counterpart of loadConfig, split out
// for unit testing (§11.4.27(A)) without touching the filesystem.
func parseConfig(b []byte) (Config, error) {
	var cfg Config
	if err := yaml.Unmarshal(b, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config yaml: %w", err)
	}

	if cfg.LLMsVerifierBin == "" {
		return Config{}, fmt.Errorf("config: llmsverifier_bin is required")
	}
	if len(cfg.Aliases) == 0 {
		return Config{}, fmt.Errorf("config: aliases must be non-empty")
	}
	if cfg.TimeoutSeconds <= 0 {
		cfg.TimeoutSeconds = defaultTimeoutSeconds
	}
	if cfg.SentinelPrefix == "" {
		cfg.SentinelPrefix = defaultSentinelPrefix
	}

	seen := make(map[string]bool, len(cfg.Aliases))
	for i, a := range cfg.Aliases {
		if a.Alias == "" {
			return Config{}, fmt.Errorf("config: aliases[%d].alias is required", i)
		}
		if seen[a.Alias] {
			return Config{}, fmt.Errorf("config: duplicate alias %q at aliases[%d]", a.Alias, i)
		}
		seen[a.Alias] = true

		if !validKinds[a.Kind] {
			return Config{}, fmt.Errorf("config: aliases[%d] (%s): invalid kind %q (must be native|provider-native|provider-router)", i, a.Alias, a.Kind)
		}
		switch a.Kind {
		case KindNative:
			if a.ConfigDir == "" {
				return Config{}, fmt.Errorf("config: aliases[%d] (%s): kind=native requires config_dir", i, a.Alias)
			}
		case KindProviderNative:
			if a.BaseURL == "" {
				return Config{}, fmt.Errorf("config: aliases[%d] (%s): kind=provider-native requires base_url", i, a.Alias)
			}
			if a.AuthTokenEnv == "" {
				return Config{}, fmt.Errorf("config: aliases[%d] (%s): kind=provider-native requires auth_token_env", i, a.Alias)
			}
		case KindProviderRouter:
			if a.BaseURL == "" {
				return Config{}, fmt.Errorf("config: aliases[%d] (%s): kind=provider-router requires base_url", i, a.Alias)
			}
		}
	}

	return cfg, nil
}
