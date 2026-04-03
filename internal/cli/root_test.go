package cli

import (
	"strings"
	"testing"
	"time"

	"github.com/mattolson/agent-sandbox/internal/testutil"
	"github.com/mattolson/agent-sandbox/internal/version"
)

func TestRootCommandIncludesExpectedCommands(t *testing.T) {
	cmd := NewRootCommand(Options{})

	want := []string{"bump", "compose", "destroy", "down", "edit", "exec", "init", "logs", "policy", "switch", "up", "version"}
	got := make([]string, 0, len(cmd.Commands()))
	for _, subcommand := range cmd.Commands() {
		got = append(got, subcommand.Name())
	}

	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("unexpected command list: got %v want %v", got, want)
	}
}

func TestVersionCommandPrintsBuildMetadata(t *testing.T) {
	cmd := NewRootCommand(Options{
		Version: version.Info{
			Version:    "v0.1.0",
			Commit:     "abcdef1234567890",
			CommitTime: time.Date(2026, time.March, 30, 22, 15, 0, 0, time.UTC),
			Dirty:      true,
			GoVersion:  "go1.26.1",
			Source:     version.SourceLDFlags,
		},
	})

	stdout, stderr, err := testutil.ExecuteCommand(cmd, "version")
	if err != nil {
		t.Fatalf("version command failed: %v", err)
	}
	if stderr != "" {
		t.Fatalf("expected no stderr, got %q", stderr)
	}

	for _, snippet := range []string{
		"Agent Sandbox v0.1.0-dirty",
		"commit: abcdef1234567890",
		"commit-time: 2026-03-30T22:15:00Z",
		"source: ldflags",
	} {
		if !strings.Contains(stdout, snippet) {
			t.Fatalf("expected version output to contain %q, got %q", snippet, stdout)
		}
	}
}

func TestPendingBumpCommandAllowsUnknownFlagsBeforeReturningPlaceholder(t *testing.T) {
	cmd := NewRootCommand(Options{})

	_, _, err := testutil.ExecuteCommand(cmd, "bump", "--agent", "claude")
	if err == nil {
		t.Fatal("expected placeholder error")
	}
	if got := err.Error(); got != "agentbox bump is not implemented in the Go CLI yet; use ./cli/bin/agentbox for now" {
		t.Fatalf("unexpected error: %q", got)
	}
}
