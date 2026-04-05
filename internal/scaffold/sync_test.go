package scaffold

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestEnsureCLIAgentRuntimeFilesCreatesMissingFilesAndPersistsState(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	runner := &syncStubRunner{digestByImage: map[string]string{"ghcr.io/mattolson/agent-sandbox-claude:latest": "ghcr.io/mattolson/agent-sandbox-claude@sha256:abc123"}}

	target, err := EnsureCLIAgentRuntimeFiles(context.Background(), SyncParams{
		RepoRoot:     repoRoot,
		Agent:        "claude",
		PersistState: true,
		Runner:       runner,
		LookupEnv: mapLookup(map[string]string{
			"AGENTBOX_ENABLE_DOTFILES":             "true",
			"AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS": "true",
			"AGENTBOX_MOUNT_CLAUDE_CONFIG":         "true",
		}),
	})
	if err != nil {
		t.Fatalf("EnsureCLIAgentRuntimeFiles failed: %v", err)
	}
	if target.ActiveAgent != "claude" {
		t.Fatalf("unexpected target: %+v", target)
	}

	persisted, err := runtime.ReadActiveTarget(repoRoot)
	if err != nil {
		t.Fatalf("ReadActiveTarget failed: %v", err)
	}
	if persisted.ActiveAgent != "claude" {
		t.Fatalf("unexpected persisted target: %+v", persisted)
	}

	base := readCompose(t, runtime.CLIBaseComposeFile(repoRoot))
	assertContains(t, base.Services.Proxy.Volumes, "../policy/user.policy.yaml:/etc/agent-sandbox/policy/user.policy.yaml:ro")

	agent := readCompose(t, runtime.CLIAgentComposeFile(repoRoot, "claude"))
	if agent.Services.Agent.Image != "ghcr.io/mattolson/agent-sandbox-claude@sha256:abc123" {
		t.Fatalf("unexpected agent image: %q", agent.Services.Agent.Image)
	}
	assertContains(t, agent.Services.Proxy.Volumes, "../policy/user.agent.claude.policy.yaml:/etc/agent-sandbox/policy/user.agent.policy.yaml:ro")
	assertContains(t, agent.Services.Proxy.Environment, "AGENTBOX_ACTIVE_AGENT=claude")

	sharedOverride := readCompose(t, runtime.CLIUserOverrideFile(repoRoot))
	assertContains(t, sharedOverride.Services.Agent.Volumes, `${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro`)
	assertContains(t, sharedOverride.Services.Agent.Volumes, `${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro`)

	agentOverride := readCompose(t, runtime.CLIUserAgentOverrideFile(repoRoot, "claude"))
	assertContains(t, agentOverride.Services.Agent.Volumes, `${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro`)
	assertContains(t, agentOverride.Services.Agent.Volumes, `${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro`)

	assertFileExists(t, runtime.SharedPolicyFile(repoRoot))
	assertFileExists(t, runtime.UserAgentPolicyFile(repoRoot, "claude"))
}

func TestEnsureSharedRuntimeConfigHelpersCreateExpectedFiles(t *testing.T) {
	repoRoot := t.TempDir()

	if err := EnsureSharedComposeOverride(repoRoot, mapLookup(map[string]string{"AGENTBOX_ENABLE_DOTFILES": "true"})); err != nil {
		t.Fatalf("EnsureSharedComposeOverride failed: %v", err)
	}
	if err := EnsureSharedPolicyFile(repoRoot); err != nil {
		t.Fatalf("EnsureSharedPolicyFile failed: %v", err)
	}
	if err := EnsureAgentPolicyFile(repoRoot, "claude"); err != nil {
		t.Fatalf("EnsureAgentPolicyFile failed: %v", err)
	}
	if err := EnsureAgentPolicyFile(repoRoot, "invalid"); err == nil {
		t.Fatal("expected invalid agent to fail")
	}

	sharedOverride := readCompose(t, runtime.CLIUserOverrideFile(repoRoot))
	assertContains(t, sharedOverride.Services.Agent.Volumes, `${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro`)
	assertFileExists(t, runtime.SharedPolicyFile(repoRoot))
	assertFileExists(t, runtime.UserAgentPolicyFile(repoRoot, "claude"))
}

func TestEnsureDevcontainerRuntimeFilesRepairsMissingMetadataAndPersistsState(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=codex\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services:\n  proxy:\n    volumes:\n      - ../policy-cli-codex.yaml:/etc/mitmproxy/policy.yaml:ro\n  agent:\n    image: agent-sandbox-codex:local\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/docker-compose.base.yml", "legacy\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/policy.override.yaml", "legacy\n")

	stderr := new(bytes.Buffer)
	target, err := EnsureDevcontainerRuntimeFiles(context.Background(), SyncParams{
		RepoRoot:     repoRoot,
		Agent:        "codex",
		PersistState: true,
		Stderr:       stderr,
	})
	if err != nil {
		t.Fatalf("EnsureDevcontainerRuntimeFiles failed: %v", err)
	}

	wantProjectName := runtime.DeriveBaseProjectName(repoRoot)
	if target.ActiveAgent != "codex" || target.DevcontainerIDE != "none" || target.ProjectName != wantProjectName {
		t.Fatalf("unexpected target: %+v", target)
	}

	if !strings.Contains(stderr.String(), "Devcontainer IDE metadata missing. Defaulting to 'none' for managed file sync.") {
		t.Fatalf("expected missing IDE warning, got %q", stderr.String())
	}
	if !strings.Contains(stderr.String(), "Project name metadata missing. Falling back to the default derived name.") {
		t.Fatalf("expected missing project name warning, got %q", stderr.String())
	}

	persisted, err := runtime.ReadActiveTarget(repoRoot)
	if err != nil {
		t.Fatalf("ReadActiveTarget failed: %v", err)
	}
	if persisted != target {
		t.Fatalf("unexpected persisted target: got %+v want %+v", persisted, target)
	}

	base := readCompose(t, runtime.CLIBaseComposeFile(repoRoot))
	if base.Name != wantProjectName {
		t.Fatalf("unexpected base project name: %q", base.Name)
	}
	assertContains(t, base.Services.Proxy.Volumes, "../policy/user.policy.yaml:/etc/agent-sandbox/policy/user.policy.yaml:ro")

	agent := readCompose(t, runtime.CLIAgentComposeFile(repoRoot, "codex"))
	assertContains(t, agent.Services.Proxy.Volumes, "../policy/user.agent.codex.policy.yaml:/etc/agent-sandbox/policy/user.agent.policy.yaml:ro")
	assertNotContains(t, agent.Services.Proxy.Volumes, "../policy-cli-codex.yaml:/etc/mitmproxy/policy.yaml:ro")
	assertContains(t, agent.Services.Proxy.Environment, "AGENTBOX_ACTIVE_AGENT=codex")

	modeFile := readCompose(t, runtime.CLIDevcontainerModeComposeFile(repoRoot))
	if modeFile.Name != runtime.ApplyModeSuffix(wantProjectName, runtime.ModeDevcontainer) {
		t.Fatalf("unexpected mode project name: %q", modeFile.Name)
	}

	policy := readPolicy(t, runtime.DevcontainerManagedPolicyFile(repoRoot))
	if len(policy.Services) != 0 {
		t.Fatalf("expected no devcontainer services for IDE none, got %v", policy.Services)
	}

	assertFileExists(t, runtime.CLIUserOverrideFile(repoRoot))
	assertFileExists(t, runtime.CLIUserAgentOverrideFile(repoRoot, "codex"))
	assertFileExists(t, runtime.DevcontainerJSONFile(repoRoot))
	assertFileExists(t, runtime.SharedPolicyFile(repoRoot))

	if _, err := os.Stat(filepath.Join(repoRoot, ".devcontainer", "docker-compose.base.yml")); !os.IsNotExist(err) {
		t.Fatalf("expected legacy devcontainer compose file to be removed, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(repoRoot, ".devcontainer", "policy.override.yaml")); !os.IsNotExist(err) {
		t.Fatalf("expected legacy devcontainer policy file to be removed, got %v", err)
	}
}

func readFile(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return data
}

// syncStubRunner returns canned image digests for scaffold sync tests.
type syncStubRunner struct {
	digestByImage map[string]string
}

func (runner *syncStubRunner) Run(_ context.Context, _ string, args []string, _ docker.CommandOptions) error {
	if len(args) != 2 || args[0] != "pull" {
		return nil
	}
	if _, ok := runner.digestByImage[args[1]]; ok {
		return nil
	}
	return nil
}

func (runner *syncStubRunner) Output(_ context.Context, _ string, args []string, _ docker.CommandOptions) ([]byte, error) {
	if len(args) == 3 && args[0] == "inspect" && strings.HasPrefix(args[1], "--format=") {
		if digest, ok := runner.digestByImage[args[2]]; ok {
			return []byte(digest + "\n"), nil
		}
	}
	return nil, nil
}
