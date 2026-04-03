package cli

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestDestroyRemovesManagedLayoutDirectories(t *testing.T) {
	repoRoot := destroyManagedRepo(t)
	runner := &fakeRunner{}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, stderr, err := testutil.ExecuteCommand(cmd, "destroy", "-f")
	if err != nil {
		t.Fatalf("destroy failed: %v", err)
	}
	if !strings.Contains(stderr, "Stopping containers") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, runtime.AgentSandboxDirName)); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("expected sandbox dir removal, got %v", statErr)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, ".devcontainer")); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("expected devcontainer dir removal, got %v", statErr)
	}
	want := [][]string{{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIDevcontainerModeComposeFile(repoRoot), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "down", "--volumes"}}
	if got := callArgs(runner.calls); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected runner calls: got %v want %v", got, want)
	}
}

func TestDestroyUsesLegacyComposeCleanupWhenNeeded(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/docker-compose.yml", "services: {}\n")

	runner := &fakeRunner{}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "destroy", "--force")
	if err != nil {
		t.Fatalf("destroy failed: %v", err)
	}
	want := [][]string{{"docker", "compose", "-f", runtime.LegacyCLIComposeFile(repoRoot), "down", "--volumes"}}
	if got := callArgs(runner.calls); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected runner calls: got %v want %v", got, want)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, runtime.AgentSandboxDirName)); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("expected sandbox dir removal, got %v", statErr)
	}
}

func TestDestroyContinuesWhenComposeShutdownFails(t *testing.T) {
	repoRoot := destroyManagedRepo(t)
	runner := &fakeRunner{runErr: errors.New("boom")}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, stderr, err := testutil.ExecuteCommand(cmd, "destroy", "-f")
	if err != nil {
		t.Fatalf("destroy failed: %v", err)
	}
	if !strings.Contains(stderr, "Continuing with filesystem cleanup") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, runtime.AgentSandboxDirName)); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("expected sandbox dir removal, got %v", statErr)
	}
}

func TestDestroyRemovesFilesWhenNoComposeStackExists(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.MustMkdirAll(t, filepath.Join(repoRoot, runtime.AgentSandboxDirName))
	testutil.MustMkdirAll(t, filepath.Join(repoRoot, ".devcontainer"))

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: &fakeRunner{}})
	_, stderr, err := testutil.ExecuteCommand(cmd, "destroy", "-f")
	if err != nil {
		t.Fatalf("destroy failed: %v", err)
	}
	if !strings.Contains(stderr, "No compose stack found. Skipping container shutdown.") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, runtime.AgentSandboxDirName)); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("expected sandbox dir removal, got %v", statErr)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, ".devcontainer")); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("expected devcontainer dir removal, got %v", statErr)
	}
}

func TestDestroyAbortsWhenUserAnswersNo(t *testing.T) {
	repoRoot := destroyManagedRepo(t)
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: &fakeRunner{}})
	cmd.SetIn(strings.NewReader("n\n"))

	_, stderr, err := testutil.ExecuteCommand(cmd, "destroy")
	if err != nil {
		t.Fatalf("destroy failed: %v", err)
	}
	if !strings.Contains(stderr, "Aborting") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, runtime.AgentSandboxDirName)); statErr != nil {
		t.Fatalf("expected sandbox dir to remain: %v", statErr)
	}
}

func destroyManagedRepo(t *testing.T) string {
	t.Helper()
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/devcontainer.json", "{}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=codex\nDEVCONTAINER_IDE=vscode\nPROJECT_NAME=repo-sandbox\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-codex:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml", "services: {}\n")
	return repoRoot
}
