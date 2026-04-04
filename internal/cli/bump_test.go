package cli

import (
	"os"
	"reflect"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestBumpFailsFastForLegacySingleFileLayouts(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/docker-compose.yml", "services: {}\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: &fakeRunner{}})
	_, _, err := testutil.ExecuteCommand(cmd, "bump")
	if err == nil {
		t.Fatal("expected legacy layout error")
	}
	for _, snippet := range []string{"does not support the legacy single-file layout", ".agent-sandbox/docker-compose.legacy.yml", "docs/upgrades/m8-layered-layout.md"} {
		if !strings.Contains(err.Error(), snippet) {
			t.Fatalf("expected error to contain %q, got %q", snippet, err.Error())
		}
	}
}

func TestBumpUpdatesManagedLayeredCLIFilesAndPreservesOverrides(t *testing.T) {
	repoRoot := t.TempDir()
	baseFile := testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: ghcr.io/example/proxy:latest\n")
	claudeFile := testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services:\n  agent:\n    image: ghcr.io/example/claude:latest\n")
	sharedOverride := testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "services:\n  agent:\n    environment:\n      - SHARED=1\n")
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")

	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("ghcr.io/example/proxy@sha256:abc123\n")}, {stdout: []byte("ghcr.io/example/claude@sha256:def456\n")}}}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, stderr, err := testutil.ExecuteCommand(cmd, "bump")
	if err != nil {
		t.Fatalf("bump failed: %v", err)
	}
	for _, snippet := range []string{"Found layered compose files (mode: cli)", "copilot layer: not initialized, skipping", "codex layer: not initialized, skipping", "Bump complete"} {
		if !strings.Contains(stderr, snippet) {
			t.Fatalf("expected stderr to contain %q, got %q", snippet, stderr)
		}
	}
	assertFileContains(t, baseFile, "ghcr.io/example/proxy@sha256:abc123")
	assertFileContains(t, claudeFile, "ghcr.io/example/claude@sha256:def456")
	assertFileContains(t, sharedOverride, "SHARED=1")
	want := [][]string{
		{"docker", "pull", "ghcr.io/example/proxy:latest"},
		{"docker", "inspect", "--format={{index .RepoDigests 0}}", "ghcr.io/example/proxy:latest"},
		{"docker", "pull", "ghcr.io/example/claude:latest"},
		{"docker", "inspect", "--format={{index .RepoDigests 0}}", "ghcr.io/example/claude:latest"},
	}
	if got := callArgs(runner.calls); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected docker calls: got %v want %v", got, want)
	}
}

func TestBumpReportsDevcontainerModeForCentralizedDevcontainerProjects(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/devcontainer.json", "{}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: ghcr.io/example/proxy:latest\n")

	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("ghcr.io/example/proxy@sha256:abc123\n")}}}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, stderr, err := testutil.ExecuteCommand(cmd, "bump")
	if err != nil {
		t.Fatalf("bump failed: %v", err)
	}
	for _, snippet := range []string{"Found layered compose files (mode: devcontainer)", "Checking images for managed devcontainer layers"} {
		if !strings.Contains(stderr, snippet) {
			t.Fatalf("expected stderr to contain %q, got %q", snippet, stderr)
		}
	}
}

func TestBumpRecognizesCorruptedDevcontainerOnlyLayoutBeforeGenericMissingLayoutError(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/devcontainer.json", "{}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: &fakeRunner{}})
	_, stderr, err := testutil.ExecuteCommand(cmd, "bump")
	if err == nil {
		t.Fatal("expected bump to fail")
	}
	if strings.Contains(err.Error(), "No layered compose layout found") {
		t.Fatalf("expected layout-specific error, got %q", err.Error())
	}
	if !strings.Contains(stderr, "Found layered compose files (mode: devcontainer)") {
		t.Fatalf("expected mode banner, got %q", stderr)
	}
	if !strings.Contains(err.Error(), runtime.CLIBaseComposeFile(repoRoot)) {
		t.Fatalf("expected missing base path in error, got %q", err.Error())
	}
}

func TestBumpHandlesExistingDigestImages(t *testing.T) {
	repoRoot := t.TempDir()
	baseFile := testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: ghcr.io/example/proxy@sha256:old123\n")
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")

	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("ghcr.io/example/proxy@sha256:new456\n")}}}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "bump")
	if err != nil {
		t.Fatalf("bump failed: %v", err)
	}
	assertFileContains(t, baseFile, "ghcr.io/example/proxy@sha256:new456")
	want := [][]string{
		{"docker", "pull", "ghcr.io/example/proxy"},
		{"docker", "inspect", "--format={{index .RepoDigests 0}}", "ghcr.io/example/proxy"},
	}
	if got := callArgs(runner.calls); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected docker calls: got %v want %v", got, want)
	}
}

func assertFileContains(t *testing.T, path string, want string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if !strings.Contains(string(data), want) {
		t.Fatalf("expected %s to contain %q, got %q", path, want, string(data))
	}
}
