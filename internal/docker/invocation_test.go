package docker

import (
	"bytes"
	"context"
	"io"
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

func TestExecRunnerRunUsesProvidedStreamsAndEnv(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	err := (ExecRunner{}).Run(context.Background(), "sh", []string{"-c", `printf '%s' "$TEST_VALUE"; printf 'warn' >&2`}, CommandOptions{
		Env:    []string{"TEST_VALUE=hello"},
		Stdout: &stdout,
		Stderr: &stderr,
	})
	if err != nil {
		t.Fatalf("ExecRunner.Run failed: %v", err)
	}
	if stdout.String() != "hello" {
		t.Fatalf("unexpected stdout: %q", stdout.String())
	}
	if stderr.String() != "warn" {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
}

func TestExecRunnerOutputCapturesStdoutAndPreservesProvidedStderr(t *testing.T) {
	var stderr bytes.Buffer

	output, err := (ExecRunner{}).Output(context.Background(), "sh", []string{"-c", `printf 'out'; printf 'warn' >&2`}, CommandOptions{
		Stderr: &stderr,
	})
	if err != nil {
		t.Fatalf("ExecRunner.Output failed: %v", err)
	}
	if string(output) != "out" {
		t.Fatalf("unexpected stdout: %q", string(output))
	}
	if stderr.String() != "warn" {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
}

func TestDockerAndComposeCommandBuildExpectedArgs(t *testing.T) {
	dockerCmd := DockerCommand(context.Background(), CommandOptions{Dir: "/workspace", Stderr: io.Discard}, "version")
	if !slices.Equal(dockerCmd.Args, []string{"docker", "version"}) {
		t.Fatalf("unexpected docker args: %v", dockerCmd.Args)
	}
	if dockerCmd.Dir != "/workspace" {
		t.Fatalf("unexpected docker dir: %q", dockerCmd.Dir)
	}

	composeCmd := ComposeCommand(context.Background(), CommandOptions{}, []string{"base.yml", "agent.yml"}, "ps")
	want := []string{"docker", "compose", "-f", "base.yml", "-f", "agent.yml", "ps"}
	if !slices.Equal(composeCmd.Args, want) {
		t.Fatalf("unexpected compose args: got %v want %v", composeCmd.Args, want)
	}
}
