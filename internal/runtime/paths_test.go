package runtime

import (
	"path/filepath"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestFindRepoRootRecognizesAgentSandboxDir(t *testing.T) {
	root := t.TempDir()
	testutil.WriteFile(t, root, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=opencode\n")
	nested := filepath.Join(root, "a", "b", "c")
	testutil.MustMkdirAll(t, nested)

	got, err := FindRepoRoot(nested)
	if err != nil {
		t.Fatalf("FindRepoRoot failed: %v", err)
	}
	if got != root {
		t.Fatalf("unexpected repo root: got %q want %q", got, root)
	}
}

func TestFindRepoRootRecognizesGitFile(t *testing.T) {
	root := t.TempDir()
	testutil.WriteFile(t, root, ".git", "gitdir: /tmp/worktree\n")
	nested := filepath.Join(root, "nested")
	testutil.MustMkdirAll(t, nested)

	got, err := FindRepoRoot(nested)
	if err != nil {
		t.Fatalf("FindRepoRoot failed: %v", err)
	}
	if got != root {
		t.Fatalf("unexpected repo root: got %q want %q", got, root)
	}
}

func TestProjectNameHelpers(t *testing.T) {
	if got := DeriveBaseProjectName("/tmp/project"); got != "project-sandbox" {
		t.Fatalf("unexpected base project name: %q", got)
	}
	if got := ApplyModeSuffix("project-sandbox", ModeCLI); got != "project-sandbox" {
		t.Fatalf("unexpected cli name: %q", got)
	}
	if got := ApplyModeSuffix("project-sandbox", ModeDevcontainer); got != "project-sandbox-devcontainer" {
		t.Fatalf("unexpected devcontainer name: %q", got)
	}
	if got := StripModeSuffix("project-sandbox-devcontainer", ModeDevcontainer); got != "project-sandbox" {
		t.Fatalf("unexpected stripped name: %q", got)
	}
	if got := DeriveProjectName("/tmp/project", ModeDevcontainer); got != "project-sandbox-devcontainer" {
		t.Fatalf("unexpected derived name: %q", got)
	}
}
