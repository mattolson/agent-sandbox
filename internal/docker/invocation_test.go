package docker

import (
	"context"
	"slices"
	"testing"
)

func TestComposeArgs(t *testing.T) {
	got := ComposeArgs([]string{"base.yml", "agent.yml"}, "config", "--no-interpolate")
	want := []string{"compose", "-f", "base.yml", "-f", "agent.yml", "config", "--no-interpolate"}
	if !slices.Equal(got, want) {
		t.Fatalf("unexpected compose args: got %v want %v", got, want)
	}
}

func TestNewCommandAppliesOptions(t *testing.T) {
	cmd := NewCommand(context.Background(), "docker", []string{"version"}, CommandOptions{
		Dir: "/workspace",
		Env: []string{"TEST_KEY=value"},
	})

	if cmd.Dir != "/workspace" {
		t.Fatalf("unexpected dir: %q", cmd.Dir)
	}
	if !slices.Contains(cmd.Args, "version") {
		t.Fatalf("expected command args to contain version: %v", cmd.Args)
	}

	found := false
	for _, entry := range cmd.Env {
		if entry == "TEST_KEY=value" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected TEST_KEY in env: %v", cmd.Env)
	}
}
