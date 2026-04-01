package cli

import (
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestPolicyConfigRunsProxyRenderHelperThroughCompose(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("services: []\n")}}}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	stdout, _, err := testutil.ExecuteCommand(cmd, "policy", "config")
	if err != nil {
		t.Fatalf("policy config failed: %v", err)
	}
	if stdout != "services: []\n" {
		t.Fatalf("unexpected stdout: %q", stdout)
	}

	want := []string{"docker", "compose", "-f", runtime.CLIBaseComposeFile(repoRoot), "-f", runtime.CLIAgentComposeFile(repoRoot, "codex"), "-f", runtime.CLIUserOverrideFile(repoRoot), "-f", runtime.CLIUserAgentOverrideFile(repoRoot, "codex"), "run", "--rm", "--no-deps", "-T", "--entrypoint", "/usr/local/bin/render-policy", "proxy"}
	if len(runner.calls) != 1 || !strings.EqualFold(runner.calls[0].method, "output") || strings.Join(runner.calls[0].args, "\n") != strings.Join(want, "\n") {
		t.Fatalf("unexpected runner call: %+v", runner.calls)
	}
}

func TestPolicyRenderAliasesPolicyConfig(t *testing.T) {
	repoRoot := layeredCLIRepo(t)
	runner := &fakeRunner{outputs: []fakeOutput{{stdout: []byte("services: []\n")}}}

	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Runner: runner})
	stdout, _, err := testutil.ExecuteCommand(cmd, "policy", "render")
	if err != nil {
		t.Fatalf("policy render failed: %v", err)
	}
	if stdout != "services: []\n" {
		t.Fatalf("unexpected stdout: %q", stdout)
	}
}

func TestPolicyConfigRejectsArguments(t *testing.T) {
	cmd := NewRootCommand(Options{WorkingDir: t.TempDir(), Runner: &fakeRunner{}})
	_, _, err := testutil.ExecuteCommand(cmd, "policy", "config", "extra")
	if err == nil || err.Error() != "agentbox policy config does not accept arguments" {
		t.Fatalf("unexpected error: %v", err)
	}
}
