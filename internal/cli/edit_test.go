package cli

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestEditComposeFailsFastForLegacyLayouts(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/docker-compose.yml", "services: {}\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, _, err := testutil.ExecuteCommand(cmd, "edit", "compose")
	if err == nil {
		t.Fatal("expected legacy layout error")
	}
	for _, snippet := range []string{"does not support the legacy single-file layout", ".devcontainer/docker-compose.legacy.yml", "docs/upgrades/m8-layered-layout.md"} {
		if !strings.Contains(err.Error(), snippet) {
			t.Fatalf("expected error to contain %q, got %q", snippet, err.Error())
		}
	}
}

func TestEditComposeRestartsContainersWhenModifiedAndRunning(t *testing.T) {
	repoRoot := layeredEditRepo(t)
	editor := writeEditorScript(t)
	logFile := filepath.Join(t.TempDir(), "editor.log")
	t.Setenv("AGENTBOX_EDITOR_LOG", logFile)
	t.Setenv("AGENTBOX_EDITOR_TOUCH", "true")

	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("running\n")}}}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner, LookupEnv: mapLookup(map[string]string{"EDITOR": editor})})
	_, stderr, err := testutil.ExecuteCommand(cmd, "edit", "compose")
	if err != nil {
		t.Fatalf("edit compose failed: %v", err)
	}
	opened, readErr := os.ReadFile(logFile)
	if readErr != nil {
		t.Fatalf("read editor log: %v", readErr)
	}
	if got := strings.TrimSpace(string(opened)); got != runtime.CLIUserOverrideFile(repoRoot) {
		t.Fatalf("unexpected editor target: %q", got)
	}
	if !strings.Contains(stderr, "Compose file was modified. Restarting containers...") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	want := [][]string{
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "claude"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "claude"), "ps", "--status", "running", "--quiet"},
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "claude"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "claude"), "up", "-d"},
	}
	if got := callArgs(runner.calls); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected runner calls: got %v want %v", got, want)
	}
}

func TestEditComposeWarnsInsteadOfRestartingWithNoRestart(t *testing.T) {
	repoRoot := layeredEditRepo(t)
	editor := writeEditorScript(t)
	t.Setenv("AGENTBOX_EDITOR_TOUCH", "true")

	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("running\n")}}}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner, LookupEnv: mapLookup(map[string]string{"EDITOR": editor})})
	_, stderr, err := testutil.ExecuteCommand(cmd, "edit", "compose", "--no-restart")
	if err != nil {
		t.Fatalf("edit compose failed: %v", err)
	}
	if !strings.Contains(stderr, "Compose file was modified, and you have containers running.") || !strings.Contains(stderr, "agentbox up -d") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	if len(runner.calls) != 1 || runner.calls[0].method != "output" {
		t.Fatalf("expected only the ps check, got %+v", runner.calls)
	}
}

func TestEditPolicyWarnsForInactiveAgentChanges(t *testing.T) {
	repoRoot := layeredEditRepo(t)
	editor := writeEditorScript(t)
	logFile := filepath.Join(t.TempDir(), "editor.log")
	t.Setenv("AGENTBOX_EDITOR_LOG", logFile)
	t.Setenv("AGENTBOX_EDITOR_TOUCH", "true")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, LookupEnv: mapLookup(map[string]string{"EDITOR": editor})})
	_, stderr, err := testutil.ExecuteCommand(cmd, "edit", "policy", "--agent", "codex")
	if err != nil {
		t.Fatalf("edit policy failed: %v", err)
	}
	if !strings.Contains(stderr, "inactive agent 'codex'") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	opened, readErr := os.ReadFile(logFile)
	if readErr != nil {
		t.Fatalf("read editor log: %v", readErr)
	}
	if got := strings.TrimSpace(string(opened)); got != runtime.UserAgentPolicyFile(repoRoot, "codex") {
		t.Fatalf("unexpected editor target: %q", got)
	}
}

func TestEditPolicyReloadsProxyWhenSharedPolicyChanges(t *testing.T) {
	repoRoot := layeredEditRepo(t)
	editor := writeEditorScript(t)
	t.Setenv("AGENTBOX_EDITOR_TOUCH", "true")

	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("proxy-container-id\n")}}}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner, LookupEnv: mapLookup(map[string]string{"EDITOR": editor})})
	_, stderr, err := testutil.ExecuteCommand(cmd, "edit", "policy")
	if err != nil {
		t.Fatalf("edit policy failed: %v", err)
	}
	if !strings.Contains(stderr, "Reloading proxy policy") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	want := [][]string{
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "claude"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "claude"), "ps", "proxy", "--status", "running", "--quiet"},
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "claude"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "claude"), "kill", "-s", "HUP", "proxy"},
	}
	if got := callArgs(runner.calls); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected runner calls: got %v want %v", got, want)
	}
}

func TestEditPolicyModeDevcontainerStillTargetsSharedLayeredPolicy(t *testing.T) {
	repoRoot := devcontainerEditRepo(t)
	editor := writeEditorScript(t)
	logFile := filepath.Join(t.TempDir(), "editor.log")
	t.Setenv("AGENTBOX_EDITOR_LOG", logFile)

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, LookupEnv: mapLookup(map[string]string{"EDITOR": editor})})
	_, stderr, err := testutil.ExecuteCommand(cmd, "edit", "policy", "--mode", "devcontainer")
	if err != nil {
		t.Fatalf("edit policy failed: %v", err)
	}
	opened, readErr := os.ReadFile(logFile)
	if readErr != nil {
		t.Fatalf("read editor log: %v", readErr)
	}
	if got := strings.TrimSpace(string(opened)); got != runtime.SharedPolicyFile(repoRoot) {
		t.Fatalf("unexpected editor target: %q", got)
	}
	if !strings.Contains(stderr, "Policy file unchanged. Skipping reload.") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
}

func layeredEditRepo(t *testing.T) string {
	t.Helper()
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=claude\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-claude:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-codex:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.claude.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/policy/user.policy.yaml", "services: []\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/policy/user.agent.claude.policy.yaml", "domains: []\n")
	return repoRoot
}

func devcontainerEditRepo(t *testing.T) string {
	t.Helper()
	repoRoot := layeredEditRepo(t)
	testutil.WriteFile(t, repoRoot, ".devcontainer/devcontainer.json", "{}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=claude\nDEVCONTAINER_IDE=vscode\nPROJECT_NAME=repo-sandbox\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")
	return repoRoot
}

func writeEditorScript(t *testing.T) string {
	t.Helper()
	script := filepath.Join(t.TempDir(), "editor.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nif [ -n \"$AGENTBOX_EDITOR_LOG\" ]; then\n  printf '%s\\n' \"$1\" > \"$AGENTBOX_EDITOR_LOG\"\nfi\nif [ \"${AGENTBOX_EDITOR_TOUCH:-false}\" = \"true\" ]; then\n  printf '\\n# modified by test\\n' >> \"$1\"\nfi\n"), 0o755); err != nil {
		t.Fatalf("write editor script: %v", err)
	}
	return script
}
