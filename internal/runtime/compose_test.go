package runtime

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestResolveComposeStackForLayeredCLI(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=codex\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml", "services: {}\n")

	stack, err := ResolveComposeStack(repoRoot)
	if err != nil {
		t.Fatalf("ResolveComposeStack failed: %v", err)
	}
	if stack.Layout != LayoutLayeredCLI {
		t.Fatalf("unexpected layout: %s", stack.Layout)
	}

	want := []string{
		filepath.Join(repoRoot, ".agent-sandbox/compose/base.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/agent.codex.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/user.override.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml"),
	}
	if !reflect.DeepEqual(stack.Files, want) {
		t.Fatalf("unexpected compose files: got %v want %v", stack.Files, want)
	}
}

func TestResolveComposeStackForDevcontainerLayout(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/devcontainer.json", "{}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=codex\nDEVCONTAINER_IDE=vscode\nPROJECT_NAME=repo-sandbox\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")

	stack, err := ResolveComposeStack(repoRoot)
	if err != nil {
		t.Fatalf("ResolveComposeStack failed: %v", err)
	}
	if stack.Layout != LayoutCentralizedDevcontainer {
		t.Fatalf("unexpected layout: %s", stack.Layout)
	}

	want := []string{
		filepath.Join(repoRoot, ".agent-sandbox/compose/base.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/agent.codex.yml"),
		filepath.Join(repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml"),
	}
	if !reflect.DeepEqual(stack.Files, want) {
		t.Fatalf("unexpected compose files: got %v want %v", stack.Files, want)
	}
}

func TestResolveComposeStackWithoutLayoutFails(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")

	_, err := ResolveComposeStack(repoRoot)
	if err == nil || err.Error() != "No layered compose layout found at "+repoRoot+". Run 'agentbox init' first." {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestComposeCommandRequiresRuntimeSync(t *testing.T) {
	for _, command := range []string{"up", "run", "create", "restart", "start"} {
		if !ComposeCommandRequiresRuntimeSync(command, false) {
			t.Fatalf("expected runtime sync for %s", command)
		}
	}
	for _, command := range []string{"ps", "logs", "exec"} {
		if ComposeCommandRequiresRuntimeSync(command, false) {
			t.Fatalf("did not expect runtime sync for %s", command)
		}
	}
	if ComposeCommandRequiresRuntimeSync("up", true) {
		t.Fatal("expected skip flag to disable runtime sync")
	}
}
