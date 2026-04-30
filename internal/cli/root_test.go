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

	want := []string{"bump", "compose", "destroy", "down", "edit", "exec", "init", "logs", "policy", "proxy", "switch", "up", "version"}
	got := make([]string, 0, len(cmd.Commands()))
	for _, subcommand := range cmd.Commands() {
		got = append(got, subcommand.Name())
	}

	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("unexpected command list: got %v want %v", got, want)
	}
}

func TestDisabledFlagParsingCommandsSupportHelpFlags(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want string
	}{
		{name: "init long help", args: []string{"init", "--help"}, want: "Initialize a project sandbox"},
		{name: "init short help", args: []string{"init", "-h"}, want: "Initialize a project sandbox"},
		{name: "switch", args: []string{"switch", "--help"}, want: "Switch the active agent"},
		{name: "edit compose", args: []string{"edit", "compose", "--help"}, want: "Edit compose overrides"},
		{name: "edit policy", args: []string{"edit", "policy", "--help"}, want: "Edit policy overrides"},
		{name: "bump", args: []string{"bump", "--help"}, want: "Refresh managed image digests"},
		{name: "destroy", args: []string{"destroy", "--help"}, want: "Remove sandbox files and resources"},
		{name: "up", args: []string{"up", "--help"}, want: "Start the sandbox runtime"},
		{name: "down", args: []string{"down", "--help"}, want: "Stop the sandbox runtime"},
		{name: "logs", args: []string{"logs", "--help"}, want: "Show runtime logs"},
		{name: "compose", args: []string{"compose", "--help"}, want: "Run docker compose against the sandbox stack"},
		{name: "exec", args: []string{"exec", "--help"}, want: "Open a shell in the sandbox container"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := NewRootCommand(Options{WorkingDir: t.TempDir()})
			stdout, stderr, err := testutil.ExecuteCommand(cmd, tt.args...)
			if err != nil {
				t.Fatalf("help command failed: %v", err)
			}
			if stderr != "" {
				t.Fatalf("expected no stderr, got %q", stderr)
			}
			if !strings.Contains(stdout, tt.want) {
				t.Fatalf("expected help output to contain %q, got %q", tt.want, stdout)
			}
		})
	}
}

func TestCustomParsedCommandHelpListsOptions(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want []string
	}{
		{name: "init", args: []string{"init", "--help"}, want: []string{"--agent", "--batch", "--ide", "--mode", "--name", "--path"}},
		{name: "switch", args: []string{"switch", "--help"}, want: []string{"--agent"}},
		{name: "edit compose", args: []string{"edit", "compose", "--help"}, want: []string{"--no-restart"}},
		{name: "edit policy", args: []string{"edit", "policy", "--help"}, want: []string{"--agent", "--mode"}},
		{name: "destroy", args: []string{"destroy", "--help"}, want: []string{"--force"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := NewRootCommand(Options{WorkingDir: t.TempDir()})
			stdout, _, err := testutil.ExecuteCommand(cmd, tt.args...)
			if err != nil {
				t.Fatalf("help command failed: %v", err)
			}
			for _, want := range tt.want {
				if !strings.Contains(stdout, want) {
					t.Fatalf("expected help output to contain %q, got %q", want, stdout)
				}
			}
		})
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

func TestBumpCommandIsImplemented(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".git", "gitdir: /tmp/worktree\n")
	cmd := NewRootCommand(Options{WorkingDir: repoRoot})

	_, _, err := testutil.ExecuteCommand(cmd, "bump")
	if err == nil {
		t.Fatal("expected missing-layout error")
	}
	if got := err.Error(); !strings.Contains(got, "Run 'agentbox init' first.") {
		t.Fatalf("unexpected error: %q", got)
	}
}
