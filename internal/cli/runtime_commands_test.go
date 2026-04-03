package cli

import (
	"context"
	"errors"
	"os"
	"reflect"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestComposeCommandUsesLayeredCLIComposeFilesInOrder(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "compose", "ps")
	if err != nil {
		t.Fatalf("compose command failed: %v", err)
	}

	want := []string{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "ps"}
	assertSingleRunCall(t, runner, want)
}

func TestComposeCommandUsesDevcontainerComposeFilesInOrder(t *testing.T) {
	repoRoot := devcontainerRepo(t)
	runner := &fakeRunner{}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "compose", "ps")
	if err != nil {
		t.Fatalf("compose command failed: %v", err)
	}

	want := []string{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIDevcontainerModeComposeFile(repoRoot), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "ps"}
	assertSingleRunCall(t, runner, want)
}

func TestComposeCommandCallsRuntimeSyncOnlyForMutatingCommands(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{}
	syncer := &spySyncer{}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner, RuntimeSyncer: syncer})
	_, _, err := testutil.ExecuteCommand(cmd, "compose", "run", "--rm", "proxy")
	if err != nil {
		t.Fatalf("compose run failed: %v", err)
	}
	if syncer.calls != 1 {
		t.Fatalf("expected one sync call, got %d", syncer.calls)
	}

	runner.calls = nil
	syncer.calls = 0
	_, _, err = testutil.ExecuteCommand(cmd, "compose", "ps")
	if err != nil {
		t.Fatalf("compose ps failed: %v", err)
	}
	if syncer.calls != 0 {
		t.Fatalf("expected no sync calls for read-only compose command, got %d", syncer.calls)
	}
}

func TestComposeCommandReResolvesFilesAfterDefaultRuntimeSync(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=codex\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services:\n  proxy:\n    environment: []\n  agent:\n    image: agent-sandbox-codex:local\n")

	runner := &fakeRunner{}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "compose", "up", "-d")
	if err != nil {
		t.Fatalf("compose up failed: %v", err)
	}
	for _, path := range []string{runtime.CLIUserOverrideFile(repoRoot), runtime.CLIUserAgentOverrideFile(repoRoot, "codex")} {
		if _, statErr := os.Stat(path); statErr != nil {
			t.Fatalf("expected %s to exist after sync: %v", path, statErr)
		}
	}
	want := []string{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "up", "-d"}
	assertSingleRunCall(t, runner, want)
}

func TestComposeCommandFailsForLegacyLayout(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".devcontainer/docker-compose.yml", "services: {}\n")

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: &fakeRunner{}})
	_, _, err := testutil.ExecuteCommand(cmd, "compose", "ps")
	if err == nil {
		t.Fatal("expected legacy layout error")
	}
	for _, snippet := range []string{"does not support the legacy single-file layout", ".devcontainer/docker-compose.legacy.yml", "docs/upgrades/m8-layered-layout.md"} {
		if !strings.Contains(err.Error(), snippet) {
			t.Fatalf("expected error to contain %q, got %q", snippet, err.Error())
		}
	}
}

func TestExecStartsContainersWhenAgentIsNotRunning(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("")}}}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "exec")
	if err != nil {
		t.Fatalf("exec command failed: %v", err)
	}

	got := callArgs(runner.calls)
	want := [][]string{
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "ps", "agent", "--status", "running", "--quiet"},
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "up", "-d"},
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "exec", "agent", "zsh"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected exec calls: got %v want %v", got, want)
	}
}

func TestExecSkipsUpWhenAgentIsAlreadyRunning(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("abc123\n")}}}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "exec", "bash")
	if err != nil {
		t.Fatalf("exec command failed: %v", err)
	}

	got := callArgs(runner.calls)
	want := [][]string{
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "ps", "agent", "--status", "running", "--quiet"},
		{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "exec", "agent", "bash"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected exec calls: got %v want %v", got, want)
	}
}

func layeredCLIRepo(t *testing.T) string {
	t.Helper()
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=codex\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.codex.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.override.yml", "services: {}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/user.agent.codex.override.yml", "services: {}\n")
	return repoRoot
}

func devcontainerRepo(t *testing.T) string {
	t.Helper()
	repoRoot := layeredCLIRepo(t)
	testutil.WriteFile(t, repoRoot, ".devcontainer/devcontainer.json", "{}\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=codex\nDEVCONTAINER_IDE=vscode\nPROJECT_NAME=repo-sandbox\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/mode.devcontainer.yml", "services: {}\n")
	return repoRoot
}

type spySyncer struct{ calls int }

func (syncer *spySyncer) Sync(context.Context, runtime.ComposeStack) error {
	syncer.calls++
	return nil
}

type fakeRunner struct {
	calls   []runnerCall
	outputs []fakeOutput
	runErr  error
}

type fakeOutput struct {
	stdout []byte
	err    error
}

type runnerCall struct {
	method string
	args   []string
	dir    string
}

func (runner *fakeRunner) Run(_ context.Context, name string, args []string, opts docker.CommandOptions) error {
	runner.calls = append(runner.calls, runnerCall{method: "run", args: append([]string{name}, args...), dir: opts.Dir})
	return runner.runErr
}

func (runner *fakeRunner) Output(_ context.Context, name string, args []string, opts docker.CommandOptions) ([]byte, error) {
	runner.calls = append(runner.calls, runnerCall{method: "output", args: append([]string{name}, args...), dir: opts.Dir})
	if len(runner.outputs) == 0 {
		return nil, nil
	}
	output := runner.outputs[0]
	runner.outputs = runner.outputs[1:]
	return output.stdout, output.err
}

func assertSingleRunCall(t *testing.T, runner *fakeRunner, want []string) {
	t.Helper()
	if len(runner.calls) != 1 {
		t.Fatalf("expected one runner call, got %d", len(runner.calls))
	}
	if runner.calls[0].method != "run" {
		t.Fatalf("expected run call, got %s", runner.calls[0].method)
	}
	if !reflect.DeepEqual(runner.calls[0].args, want) {
		t.Fatalf("unexpected runner args: got %v want %v", runner.calls[0].args, want)
	}
}

func callArgs(calls []runnerCall) [][]string {
	result := make([][]string, 0, len(calls))
	for _, call := range calls {
		result = append(result, call.args)
	}
	return result
}

var errOutput = errors.New("output failed")
