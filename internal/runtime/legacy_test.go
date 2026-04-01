package runtime

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestAbortIfUnsupportedLegacyLayoutIncludesUpgradeGuidance(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/docker-compose.yml", "services: {}\n")

	err := AbortIfUnsupportedLegacyLayout(repoRoot, "compose", "", "", "")
	if err == nil {
		t.Fatal("expected legacy layout error")
	}
	for _, snippet := range []string{
		"agentbox compose does not support the legacy single-file layout.",
		".devcontainer/docker-compose.yml -> .devcontainer/docker-compose.legacy.yml",
		"docs/upgrades/m8-layered-layout.md",
	} {
		if !strings.Contains(err.Error(), snippet) {
			t.Fatalf("expected legacy error to contain %q, got %q", snippet, err.Error())
		}
	}
}

func TestUnsupportedLegacyLayoutFilesFollowsExpectedOrder(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/docker-compose.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/docker-compose.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/policy-cli-claude.yaml", "services: []\n")

	files := UnsupportedLegacyLayoutFiles(repoRoot)
	want := []string{
		filepath.Join(repoRoot, ".agent-sandbox/docker-compose.yml"),
		filepath.Join(repoRoot, ".devcontainer/docker-compose.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/policy-cli-claude.yaml"),
	}
	if strings.Join(files, "\n") != strings.Join(want, "\n") {
		t.Fatalf("unexpected files: got %v want %v", files, want)
	}
}
