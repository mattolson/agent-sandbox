package cli

import (
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestProxyReloadSendsSIGHUPThroughCompose(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	stdout, _, err := testutil.ExecuteCommand(cmd, "proxy", "reload")
	if err != nil {
		t.Fatalf("proxy reload failed: %v", err)
	}
	if !strings.Contains(stdout, "Sent SIGHUP to proxy") {
		t.Fatalf("unexpected stdout: %q", stdout)
	}

	want := []string{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "kill", "-s", "HUP", "proxy"}
	assertSingleRunCall(t, runner, want)
}

func TestProxyLogsAliasesComposeLogsProxy(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	_, _, err := testutil.ExecuteCommand(cmd, "proxy", "logs", "-f", "--tail=20")
	if err != nil {
		t.Fatalf("proxy logs failed: %v", err)
	}

	want := []string{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "logs", "proxy", "-f", "--tail=20"}
	assertSingleRunCall(t, runner, want)
}

func TestProxyReloadRejectsArguments(t *testing.T) {
	cmd := NewRootCommand(Options{WorkingDir: t.TempDir(), Runner: &fakeRunner{}})
	_, _, err := testutil.ExecuteCommand(cmd, "proxy", "reload", "extra")
	if err == nil {
		t.Fatal("expected error for extra args")
	}
}
