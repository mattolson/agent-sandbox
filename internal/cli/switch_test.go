package cli

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestSwitchRejectsInvalidAgentBeforeLegacyLayoutHandling(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.MustMkdirAll(t, filepath.Join(repoRoot, runtime.AgentSandboxDirName))
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/docker-compose.yml", "services: {}\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, _, err := testutil.ExecuteCommand(cmd, "switch", "--agent", "invalid")
	if err == nil {
		t.Fatal("expected invalid agent error")
	}
	if got := err.Error(); got != "Invalid agent: invalid (expected: claude codex gemini opencode pi copilot factory)" {
		t.Fatalf("unexpected error: %q", got)
	}
	if strings.Contains(err.Error(), "legacy single-file layout") {
		t.Fatalf("expected validation to happen before legacy handling: %q", err.Error())
	}
}

func TestSwitchFailsWhenSandboxIsNotInitialized(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, _, err := testutil.ExecuteCommand(cmd, "switch", "--agent", "claude")
	if err == nil || !strings.Contains(err.Error(), "Run 'agentbox init' first.") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestSwitchSameAgentRefreshesLayeredRuntimeFiles(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=claude\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-claude:local\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, stderr, err := testutil.ExecuteCommand(cmd, "switch", "--agent", "claude")
	if err != nil {
		t.Fatalf("switch failed: %v", err)
	}
	if !strings.Contains(stderr, "Refreshed layered runtime files.") {
		t.Fatalf("expected refresh message, got %q", stderr)
	}
	for _, path := range []string{
		runtime.CLIUserOverrideFile(repoRoot),
		runtime.CLIUserAgentOverrideFile(repoRoot, "claude"),
		runtime.SharedPolicyFile(repoRoot),
		runtime.UserAgentPolicyFile(repoRoot, "claude"),
	} {
		if _, statErr := os.Stat(path); statErr != nil {
			t.Fatalf("expected %s to exist: %v", path, statErr)
		}
	}
}

func TestSwitchPreservesExistingUserOwnedFiles(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=claude\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-claude:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-codex:local\n")
	sharedOverride := testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "shared override\n")
	activeOverride := testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.claude.override.yml", "claude override\n")
	targetOverride := testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml", "codex override\n")
	sharedPolicy := testutil.WriteFile(t, repoRoot, ".agent-sandbox/policy/user.policy.yaml", "services:\n  - github\n")
	activePolicy := testutil.WriteFile(t, repoRoot, ".agent-sandbox/policy/user.agent.claude.policy.yaml", "domains:\n  - api.anthropic.com\n")
	targetPolicy := testutil.WriteFile(t, repoRoot, ".agent-sandbox/policy/user.agent.codex.policy.yaml", "domains:\n  - api.openai.com\n")

	runner := &fakeRunner{}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, stderr, err := testutil.ExecuteCommand(cmd, "switch", "--agent", "codex")
	if err != nil {
		t.Fatalf("switch failed: %v", err)
	}
	if !strings.Contains(stderr, "Active agent set to 'codex'.") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	for path, want := range map[string]string{
		sharedOverride: "shared override\n",
		activeOverride: "claude override\n",
		targetOverride: "codex override\n",
		sharedPolicy:   "services:\n  - github\n",
		activePolicy:   "domains:\n  - api.anthropic.com\n",
		targetPolicy:   "domains:\n  - api.openai.com\n",
	} {
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			t.Fatalf("read %s: %v", path, readErr)
		}
		if string(data) != want {
			t.Fatalf("unexpected contents for %s: got %q want %q", path, string(data), want)
		}
	}
	target, err := runtime.ReadActiveTarget(repoRoot)
	if err != nil {
		t.Fatalf("ReadActiveTarget failed: %v", err)
	}
	if target.ActiveAgent != "codex" {
		t.Fatalf("unexpected active agent after switch: %+v", target)
	}
}

func TestSwitchRestartsRunningContainersAfterWritingNewState(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=claude\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-claude:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-codex:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.claude.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml", "services: {}\n")

	runner := &switchOrderRunner{repoRoot: repoRoot}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, stderr, err := testutil.ExecuteCommand(cmd, "switch", "--agent", "codex")
	if err != nil {
		t.Fatalf("switch failed: %v", err)
	}
	if !strings.Contains(stderr, "Restarting containers to apply the switch") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	want := [][]string{
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "claude"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "claude"), "ps", "--status", "running", "--quiet"},
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "claude"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "claude"), "down"},
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "up", "-d"},
	}
	if got := callArgs(runner.calls); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected compose calls: got %v want %v", got, want)
	}
	if !strings.Contains(runner.downState, "ACTIVE_AGENT=claude\n") {
		t.Fatalf("expected down to see old state, got %q", runner.downState)
	}
	if !strings.Contains(runner.upState, "ACTIVE_AGENT=codex\n") {
		t.Fatalf("expected up to see new state, got %q", runner.upState)
	}
}

func TestSwitchSameAgentRefreshesDevcontainerRuntimeFiles(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/devcontainer.json", "{}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=claude\nDEVCONTAINER_IDE=vscode\nPROJECT_NAME=repo-sandbox\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "name: repo-sandbox\nservices:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-claude:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, stderr, err := testutil.ExecuteCommand(cmd, "switch", "--agent", "claude")
	if err != nil {
		t.Fatalf("switch failed: %v", err)
	}
	if !strings.Contains(stderr, "Refreshed layered runtime files.") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
	if _, statErr := os.Stat(filepath.Join(repoRoot, ".devcontainer", "devcontainer.user.json")); statErr != nil {
		t.Fatalf("expected devcontainer.user.json to exist: %v", statErr)
	}
}

// switchOrderRunner records state observed across down and up calls during switch tests.
type switchOrderRunner struct {
	repoRoot  string
	calls     []runnerCall
	downState string
	upState   string
}

func (runner *switchOrderRunner) Run(_ context.Context, name string, args []string, opts docker.CommandOptions) error {
	runner.calls = append(runner.calls, runnerCall{method: "run", args: append([]string{name}, args...), dir: opts.Dir})
	state, _ := os.ReadFile(runtime.ActiveTargetFile(runner.repoRoot))
	if len(args) > 0 && args[len(args)-1] == "down" {
		runner.downState = string(state)
	}
	if len(args) > 1 && args[len(args)-2] == "up" && args[len(args)-1] == "-d" {
		runner.upState = string(state)
	}
	return nil
}

func (runner *switchOrderRunner) Output(_ context.Context, name string, args []string, opts docker.CommandOptions) ([]byte, error) {
	runner.calls = append(runner.calls, runnerCall{method: "output", args: append([]string{name}, args...), dir: opts.Dir})
	return []byte("running\n"), nil
}
