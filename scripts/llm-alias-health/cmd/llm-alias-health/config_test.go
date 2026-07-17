package main

// config_test.go -- UNIT tests (§11.4.27(A)) for config parsing: pure
// function, no I/O, no subprocess.

import (
	"strings"
	"testing"
)

const validYAML = `
llmsverifier_bin: /usr/local/bin/claude-alias-probe
timeout_seconds: 45
sentinel_prefix: "TEST_PREFIX_"
aliases:
  - alias: claude1
    kind: native
    config_dir: /home/user/.claude-claude1
    model: claude-opus-4-8
  - alias: zai-router
    kind: provider-router
    base_url: http://127.0.0.1:3456
  - alias: some-provider
    kind: provider-native
    base_url: https://api.example.com
    auth_token_env: SOME_PROVIDER_TOKEN
    model: some-model
`

func TestParseConfig_Valid(t *testing.T) {
	cfg, err := parseConfig([]byte(validYAML))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.LLMsVerifierBin != "/usr/local/bin/claude-alias-probe" {
		t.Fatalf("unexpected llmsverifier_bin: %q", cfg.LLMsVerifierBin)
	}
	if len(cfg.Aliases) != 3 {
		t.Fatalf("expected 3 aliases, got %d", len(cfg.Aliases))
	}
	if cfg.TimeoutSeconds != 45 {
		t.Fatalf("expected timeout_seconds=45, got %d", cfg.TimeoutSeconds)
	}
	if cfg.Aliases[0].Kind != KindNative || cfg.Aliases[1].Kind != KindProviderRouter || cfg.Aliases[2].Kind != KindProviderNative {
		t.Fatalf("unexpected kinds: %+v", cfg.Aliases)
	}
}

func TestParseConfig_DefaultsApplied(t *testing.T) {
	const yaml = `
llmsverifier_bin: /bin/probe
aliases:
  - alias: a1
    kind: native
    config_dir: /tmp/x
`
	cfg, err := parseConfig([]byte(yaml))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.TimeoutSeconds != defaultTimeoutSeconds {
		t.Fatalf("expected default timeout %d, got %d", defaultTimeoutSeconds, cfg.TimeoutSeconds)
	}
	if cfg.SentinelPrefix != defaultSentinelPrefix {
		t.Fatalf("expected default sentinel prefix %q, got %q", defaultSentinelPrefix, cfg.SentinelPrefix)
	}
}

func TestParseConfig_MissingBinIsError(t *testing.T) {
	const yaml = `
aliases:
  - alias: a1
    kind: native
    config_dir: /tmp/x
`
	if _, err := parseConfig([]byte(yaml)); err == nil || !strings.Contains(err.Error(), "llmsverifier_bin") {
		t.Fatalf("expected llmsverifier_bin error, got %v", err)
	}
}

func TestParseConfig_EmptyAliasesIsError(t *testing.T) {
	const yaml = `llmsverifier_bin: /bin/probe`
	if _, err := parseConfig([]byte(yaml)); err == nil || !strings.Contains(err.Error(), "aliases must be non-empty") {
		t.Fatalf("expected empty-aliases error, got %v", err)
	}
}

func TestParseConfig_DuplicateAliasIsError(t *testing.T) {
	const yaml = `
llmsverifier_bin: /bin/probe
aliases:
  - alias: dup
    kind: native
    config_dir: /tmp/a
  - alias: dup
    kind: native
    config_dir: /tmp/b
`
	if _, err := parseConfig([]byte(yaml)); err == nil || !strings.Contains(err.Error(), "duplicate alias") {
		t.Fatalf("expected duplicate-alias error, got %v", err)
	}
}

func TestParseConfig_InvalidKindIsError(t *testing.T) {
	const yaml = `
llmsverifier_bin: /bin/probe
aliases:
  - alias: bad
    kind: not-a-kind
`
	if _, err := parseConfig([]byte(yaml)); err == nil || !strings.Contains(err.Error(), "invalid kind") {
		t.Fatalf("expected invalid-kind error, got %v", err)
	}
}

func TestParseConfig_NativeRequiresConfigDir(t *testing.T) {
	const yaml = `
llmsverifier_bin: /bin/probe
aliases:
  - alias: n1
    kind: native
`
	if _, err := parseConfig([]byte(yaml)); err == nil || !strings.Contains(err.Error(), "requires config_dir") {
		t.Fatalf("expected config_dir-required error, got %v", err)
	}
}

func TestParseConfig_ProviderNativeRequiresBaseURLAndAuthTokenEnv(t *testing.T) {
	const yamlNoBase = `
llmsverifier_bin: /bin/probe
aliases:
  - alias: pn1
    kind: provider-native
    auth_token_env: X
`
	if _, err := parseConfig([]byte(yamlNoBase)); err == nil || !strings.Contains(err.Error(), "requires base_url") {
		t.Fatalf("expected base_url-required error, got %v", err)
	}

	const yamlNoToken = `
llmsverifier_bin: /bin/probe
aliases:
  - alias: pn1
    kind: provider-native
    base_url: https://api.example.com
`
	if _, err := parseConfig([]byte(yamlNoToken)); err == nil || !strings.Contains(err.Error(), "requires auth_token_env") {
		t.Fatalf("expected auth_token_env-required error, got %v", err)
	}
}

func TestParseConfig_ProviderRouterRequiresBaseURL(t *testing.T) {
	const yaml = `
llmsverifier_bin: /bin/probe
aliases:
  - alias: pr1
    kind: provider-router
`
	if _, err := parseConfig([]byte(yaml)); err == nil || !strings.Contains(err.Error(), "requires base_url") {
		t.Fatalf("expected base_url-required error, got %v", err)
	}
}

func TestParseConfig_MalformedYAMLIsError(t *testing.T) {
	if _, err := parseConfig([]byte("not: [valid yaml: structure")); err == nil {
		t.Fatal("expected a parse error for malformed YAML")
	}
}

func TestLoadConfig_MissingFile(t *testing.T) {
	if _, err := loadConfig("/nonexistent/path/health_config.yaml"); err == nil {
		t.Fatal("expected an error for a missing config file")
	}
}

func TestArgsForAlias_NativeKind(t *testing.T) {
	a := AliasConfig{Alias: "n1", Kind: KindNative, ConfigDir: "/tmp/x", Model: "opus"}
	args := argsForAlias(a, "SENTINEL_1", 30)
	got := strings.Join(args, " ")
	for _, want := range []string{"--kind native", "--sentinel SENTINEL_1", "--timeout 30", "--model opus", "--config-dir /tmp/x"} {
		if !strings.Contains(got, want) {
			t.Fatalf("expected args to contain %q, got %q", want, got)
		}
	}
}

func TestArgsForAlias_ProviderNativeKind(t *testing.T) {
	a := AliasConfig{Alias: "pn1", Kind: KindProviderNative, BaseURL: "https://x", AuthTokenEnv: "TOK"}
	args := argsForAlias(a, "S2", 10)
	got := strings.Join(args, " ")
	for _, want := range []string{"--base-url https://x", "--auth-token-env TOK"} {
		if !strings.Contains(got, want) {
			t.Fatalf("expected args to contain %q, got %q", want, got)
		}
	}
}

func TestArgsForAlias_ProviderRouterKind_OptionalAPIKeyEnv(t *testing.T) {
	a := AliasConfig{Alias: "pr1", Kind: KindProviderRouter, BaseURL: "http://127.0.0.1:3456"}
	args := argsForAlias(a, "S3", 10)
	got := strings.Join(args, " ")
	if strings.Contains(got, "--api-key-env") {
		t.Fatalf("did not expect --api-key-env when APIKeyEnv is empty, got %q", got)
	}

	a.APIKeyEnv = "MY_KEY_ENV"
	args = argsForAlias(a, "S3", 10)
	got = strings.Join(args, " ")
	if !strings.Contains(got, "--api-key-env MY_KEY_ENV") {
		t.Fatalf("expected --api-key-env MY_KEY_ENV, got %q", got)
	}
}
