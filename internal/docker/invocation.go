package docker

import (
	"context"
	"io"
	"os"
	"os/exec"
)

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
	if len(opts.Env) > 0 {
		cmd.Env = append(os.Environ(), opts.Env...)
	}
	cmd.Stdin = opts.Stdin
	cmd.Stdout = opts.Stdout
	cmd.Stderr = opts.Stderr
	return cmd
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
