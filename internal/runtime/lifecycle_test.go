package runtime

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestInitializationHelpersAndLegacyDestroyComposeFile(t *testing.T) {
	repoRoot := t.TempDir()
	if AgentSandboxInitialized(repoRoot) {
		t.Fatal("did not expect sandbox to be initialized")
	}
	if CLILayeredComposeInitialized(repoRoot) {
		t.Fatal("did not expect layered CLI compose to be initialized")
	}
	if DevcontainerCentralizedRuntimeInitialized(repoRoot) {
		t.Fatal("did not expect devcontainer runtime to be initialized")
	}
	if file, ok := LegacyDestroyComposeFile(repoRoot); ok || file != "" {
		t.Fatalf("unexpected legacy destroy compose file: %q %t", file, ok)
	}

	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/docker-compose.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/docker-compose.yml", "services: {}\n")

	if !AgentSandboxInitialized(repoRoot) {
		t.Fatal("expected sandbox to be initialized")
	}
	if !CLILayeredComposeInitialized(repoRoot) {
		t.Fatal("expected layered CLI compose to be initialized")
	}
	if !DevcontainerCentralizedRuntimeInitialized(repoRoot) {
		t.Fatal("expected devcontainer runtime to be initialized")
	}
	if file, ok := LegacyDestroyComposeFile(repoRoot); !ok || file != LegacyCLIComposeFile(repoRoot) {
		t.Fatalf("unexpected legacy destroy compose file: %q %t", file, ok)
	}
}

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

func TestResolveComposeFilesForLayoutUsesLayoutSpecificEmitters(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml", "services: {}\n")

	layered, err := ResolveComposeFilesForLayout(repoRoot, LayoutLayeredCLI, "codex")
	if err != nil {
		t.Fatalf("ResolveComposeFilesForLayout layered failed: %v", err)
	}
	if !reflect.DeepEqual(layered, []string{
		filepath.Join(repoRoot, ".agent-sandbox/compose/base.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/agent.codex.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/user.override.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml"),
	}) {
		t.Fatalf("unexpected layered files: %v", layered)
	}

	devcontainer, err := ResolveComposeFilesForLayout(repoRoot, LayoutCentralizedDevcontainer, "codex")
	if err != nil {
		t.Fatalf("ResolveComposeFilesForLayout devcontainer failed: %v", err)
	}
	if !reflect.DeepEqual(devcontainer, []string{
		filepath.Join(repoRoot, ".agent-sandbox/compose/base.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/agent.codex.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/user.override.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml"),
	}) {
		t.Fatalf("unexpected devcontainer files: %v", devcontainer)
	}

	unknown, err := ResolveComposeFilesForLayout(repoRoot, Layout("unknown"), "codex")
	if err != nil {
		t.Fatalf("unexpected error for unknown layout: %v", err)
	}
	if unknown != nil {
		t.Fatalf("expected nil files for unknown layout, got %v", unknown)
	}
}
