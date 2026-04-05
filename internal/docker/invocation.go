package docker

import (
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
)

// Runner models the subset of exec.Cmd behavior this package needs.
//
// It follows the same split as exec.Cmd: Run streams through configured stdio,
// while Output captures stdout for command results the caller needs to inspect.
type Runner interface {
	// Run executes the command with the provided stdio wiring and returns only an error status.
	Run(ctx context.Context, name string, args []string, opts CommandOptions) error
	// Output executes the command and returns captured stdout while honoring the provided stderr wiring.
	Output(ctx context.Context, name string, args []string, opts CommandOptions) ([]byte, error)
}

// ExecRunner executes commands with os/exec.
type ExecRunner struct{}

// CommandOptions configures command execution and stdio wiring.
type CommandOptions struct {
	Dir    string
	Env    []string
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
}

func NewCommand(ctx context.Context, name string, args []string, opts CommandOptions) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = opts.Dir
	cmd.Env = append(os.Environ(), opts.Env...)
	cmd.Stdin = opts.Stdin
	cmd.Stdout = opts.Stdout
	cmd.Stderr = opts.Stderr
	return cmd
}

func (ExecRunner) Run(ctx context.Context, name string, args []string, opts CommandOptions) error {
	return NewCommand(ctx, name, args, opts).Run()
}

func (ExecRunner) Output(ctx context.Context, name string, args []string, opts CommandOptions) ([]byte, error) {
	var stdout bytes.Buffer
	cmd := NewCommand(ctx, name, args, opts)
	cmd.Stdout = &stdout
	if cmd.Stderr == nil {
		cmd.Stderr = io.Discard
	}
	err := cmd.Run()
	return stdout.Bytes(), err
}

func DockerCommand(ctx context.Context, opts CommandOptions, args ...string) *exec.Cmd {
	return NewCommand(ctx, "docker", args, opts)
}

func ComposeArgs(files []string, args ...string) []string {
	composeArgs := []string{"compose"}
	for _, file := range files {
		composeArgs = append(composeArgs, "-f", file)
	}

	return append(composeArgs, args...)
}

func ComposeCommand(ctx context.Context, opts CommandOptions, files []string, args ...string) *exec.Cmd {
	return DockerCommand(ctx, opts, ComposeArgs(files, args...)...)
}
