package runtime

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestPreferredManagedLayoutPrefersDevcontainerWhenBothLayoutsExist(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")

	layout, ok := PreferredManagedLayout(repoRoot)
	if !ok || layout != LayoutCentralizedDevcontainer {
		t.Fatalf("unexpected layout: %v %t", layout, ok)
	}
}

func TestExistingManagedAgentLayersReturnsInitializedAgentsInSupportedOrder(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.factory.yml", "services: {}\n")

	got := ExistingManagedAgentLayers(repoRoot)
	want := []ManagedAgentLayer{
		{Agent: "claude", File: filepath.Join(repoRoot, ".agent-sandbox/compose/agent.claude.yml")},
		{Agent: "codex", File: filepath.Join(repoRoot, ".agent-sandbox/compose/agent.codex.yml")},
		{Agent: "factory", File: filepath.Join(repoRoot, ".agent-sandbox/compose/agent.factory.yml")},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected layers: got %v want %v", got, want)
	}
}
