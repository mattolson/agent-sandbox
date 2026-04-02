package runtime

import (
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestParseTargetStateParsesShellEscapedValues(t *testing.T) {
	data := []byte(strings.Join([]string{
		"# Managed by agentbox",
		"ACTIVE_AGENT=opencode",
		"DEVCONTAINER_IDE=jetbrains",
		"PROJECT_NAME=hello\\ world",
	}, "\n"))

	target, err := ParseTargetState(data)
	if err != nil {
		t.Fatalf("ParseTargetState failed: %v", err)
	}

	if target.ActiveAgent != "opencode" || target.DevcontainerIDE != "jetbrains" || target.ProjectName != "hello world" {
		t.Fatalf("unexpected target state: %+v", target)
	}
}

func TestReadActiveTargetValidatesAgent(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=opencode\nPROJECT_NAME=agent-sandbox\n")

	target, err := ReadActiveTarget(repoRoot)
	if err != nil {
		t.Fatalf("ReadActiveTarget failed: %v", err)
	}
	if target.ActiveAgent != "opencode" {
		t.Fatalf("unexpected agent: %q", target.ActiveAgent)
	}
}

func TestReadActiveTargetRequiresActiveAgent(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "PROJECT_NAME=agent-sandbox\n")

	if _, err := ReadActiveTarget(repoRoot); err == nil {
		t.Fatal("expected missing ACTIVE_AGENT to fail")
	}
}

func TestWriteTargetStateRoundTripsShellEscapedValues(t *testing.T) {
	repoRoot := t.TempDir()
	target := ActiveTarget{ActiveAgent: "opencode", DevcontainerIDE: "jetbrains", ProjectName: "hello world"}

	if err := WriteTargetState(repoRoot, target); err != nil {
		t.Fatalf("WriteTargetState failed: %v", err)
	}

	parsed, err := ReadActiveTarget(repoRoot)
	if err != nil {
		t.Fatalf("ReadActiveTarget failed: %v", err)
	}
	if parsed != target {
		t.Fatalf("unexpected round-trip target: got %+v want %+v", parsed, target)
	}
}
