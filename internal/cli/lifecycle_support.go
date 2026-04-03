package cli

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"time"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/spf13/cobra"
)

type fileSignature struct {
	exists  bool
	modTime time.Time
	size    int64
}

func commandPrompter(cmd *cobra.Command, override Prompter) Prompter {
	if override != nil {
		return override
	}

	return newIOPrompter(cmd.InOrStdin(), cmd.ErrOrStderr())
}

func promptYesNo(prompter Prompter, prompt string, defaultValue bool) (bool, error) {
	defaultLabel := "[y/N]:"
	if defaultValue {
		defaultLabel = "[Y/n]:"
	}

	for {
		response, err := prompter.ReadLine(fmt.Sprintf("%s %s", prompt, defaultLabel))
		if err != nil {
			return false, err
		}
		switch response {
		case "", "y", "Y", "n", "N":
		default:
			continue
		}

		switch response {
		case "", "y", "Y":
			return response != "" || defaultValue, nil
		default:
			return false, nil
		}
	}
}

func currentTargetIfExists(repoRoot string) (runtime.ActiveTarget, error) {
	target, err := runtime.ReadActiveTarget(repoRoot)
	if errors.Is(err, os.ErrNotExist) {
		return runtime.ActiveTarget{}, nil
	}

	return target, err
}

func composeStackForLayout(repoRoot string, layout runtime.Layout, target runtime.ActiveTarget) (runtime.ComposeStack, error) {
	files, err := runtime.ResolveComposeFilesForLayout(repoRoot, layout, target.ActiveAgent)
	if err != nil {
		return runtime.ComposeStack{}, err
	}

	return runtime.ComposeStack{
		RepoRoot: repoRoot,
		Layout:   layout,
		Target:   target,
		Files:    files,
	}, nil
}

func runComposeCommand(ctx context.Context, runner docker.Runner, stack runtime.ComposeStack, cmd *cobra.Command, args ...string) error {
	return runner.Run(ctx, "docker", docker.ComposeArgs(stack.Files, args...), docker.CommandOptions{
		Dir:    stack.RepoRoot,
		Stdin:  cmd.InOrStdin(),
		Stdout: cmd.OutOrStdout(),
		Stderr: cmd.ErrOrStderr(),
	})
}

func outputComposeCommand(ctx context.Context, runner docker.Runner, stack runtime.ComposeStack, args ...string) ([]byte, error) {
	return runner.Output(ctx, "docker", docker.ComposeArgs(stack.Files, args...), docker.CommandOptions{
		Dir:    stack.RepoRoot,
		Stderr: os.Stderr,
	})
}

func resolveEditorFromLookup(lookup func(string) string) (runtime.Editor, error) {
	if lookup == nil {
		return runtime.ResolveEditor()
	}

	return runtime.ResolveEditorFromEnv(map[string]string{
		"VISUAL": lookup("VISUAL"),
		"EDITOR": lookup("EDITOR"),
	}, nil)
}

func runEditor(ctx context.Context, cmd *cobra.Command, editor runtime.Editor, file string) error {
	args := editor.CommandArgs(file)
	process := exec.CommandContext(ctx, args[0], args[1:]...)
	process.Stdin = cmd.InOrStdin()
	process.Stdout = cmd.OutOrStdout()
	process.Stderr = cmd.ErrOrStderr()
	return process.Run()
}

func statFile(path string) (fileSignature, error) {
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return fileSignature{}, nil
	}
	if err != nil {
		return fileSignature{}, err
	}

	return fileSignature{exists: true, modTime: info.ModTime(), size: info.Size()}, nil
}

func fileChanged(before fileSignature, after fileSignature) bool {
	if before.exists != after.exists {
		return true
	}
	if !before.exists && !after.exists {
		return false
	}

	return !before.modTime.Equal(after.modTime) || before.size != after.size
}

func envTrue(lookup func(string) string, name string) bool {
	if lookup == nil {
		return false
	}
	value := lookup(name)
	return value == "1" || value == "true" || value == "TRUE" || value == "True"
}
