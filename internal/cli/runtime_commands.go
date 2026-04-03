package cli

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/spf13/cobra"
)

type RuntimeSyncer interface {
	Sync(context.Context, runtime.ComposeStack) error
}

type noopRuntimeSyncer struct{}

func (noopRuntimeSyncer) Sync(context.Context, runtime.ComposeStack) error {
	return nil
}

type commandDeps struct {
	workingDir string
	runner     docker.Runner
	syncer     RuntimeSyncer
}

func newCommandDeps(opts Options) commandDeps {
	workingDir := opts.WorkingDir
	if workingDir == "" {
		workingDir, _ = os.Getwd()
	}

	runner := opts.Runner
	if runner == nil {
		runner = docker.ExecRunner{}
	}

	syncer := opts.RuntimeSyncer
	if syncer == nil {
		syncer = scaffoldRuntimeSyncer{runner: runner, lookupEnv: opts.LookupEnv}
	}

	return commandDeps{
		workingDir: workingDir,
		runner:     runner,
		syncer:     syncer,
	}
}

func newRuntimeComposeCommand(use string, short string, commandName string, prefix []string, deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                use,
		Short:              short,
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runComposePassthrough(cmd, deps, commandName, append(append([]string{}, prefix...), args...))
		},
	}
}

func runComposePassthrough(cmd *cobra.Command, deps commandDeps, commandName string, composeArgs []string) error {
	stack, err := resolveComposeStackForCommand(deps, commandName)
	if err != nil {
		return err
	}

	if len(composeArgs) > 0 && runtime.ComposeCommandRequiresRuntimeSync(composeArgs[0], shouldSkipRuntimeSync()) {
		if err := deps.syncer.Sync(cmd.Context(), stack); err != nil {
			return err
		}
		stack, err = resolveComposeStackForCommand(deps, commandName)
		if err != nil {
			return err
		}
	}

	return deps.runner.Run(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, composeArgs...), docker.CommandOptions{
		Dir:    stack.RepoRoot,
		Stdin:  cmd.InOrStdin(),
		Stdout: cmd.OutOrStdout(),
		Stderr: cmd.ErrOrStderr(),
	})
}

func newExecCommand(deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                "exec",
		Short:              "Open a shell in the sandbox container",
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			stack, err := resolveComposeStackForCommand(deps, "exec")
			if err != nil {
				return err
			}

			output, err := deps.runner.Output(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, "ps", "agent", "--status", "running", "--quiet"), docker.CommandOptions{
				Dir:    stack.RepoRoot,
				Stderr: io.Discard,
			})
			running := strings.TrimSpace(string(output))
			if err != nil {
				running = ""
			}

			if running == "" {
				if runtime.ComposeCommandRequiresRuntimeSync("up", shouldSkipRuntimeSync()) {
					if err := deps.syncer.Sync(cmd.Context(), stack); err != nil {
						return err
					}
					stack, err = resolveComposeStackForCommand(deps, "exec")
					if err != nil {
						return err
					}
				}
				if err := deps.runner.Run(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, "up", "-d"), docker.CommandOptions{
					Dir:    stack.RepoRoot,
					Stdin:  cmd.InOrStdin(),
					Stdout: cmd.OutOrStdout(),
					Stderr: cmd.ErrOrStderr(),
				}); err != nil {
					return err
				}
			}

			execArgs := []string{"exec", "agent"}
			if len(args) == 0 {
				execArgs = append(execArgs, "zsh")
			} else {
				execArgs = append(execArgs, args...)
			}

			return deps.runner.Run(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, execArgs...), docker.CommandOptions{
				Dir:    stack.RepoRoot,
				Stdin:  cmd.InOrStdin(),
				Stdout: cmd.OutOrStdout(),
				Stderr: cmd.ErrOrStderr(),
			})
		},
	}
}

func resolveComposeStackForCommand(deps commandDeps, commandName string) (runtime.ComposeStack, error) {
	repoRoot, err := runtime.FindRepoRoot(deps.workingDir)
	if err != nil {
		return runtime.ComposeStack{}, err
	}
	if err := runtime.AbortIfUnsupportedLegacyLayout(repoRoot, commandName, "", "", ""); err != nil {
		return runtime.ComposeStack{}, err
	}

	return runtime.ResolveComposeStack(repoRoot)
}

func shouldSkipRuntimeSync() bool {
	value, ok := os.LookupEnv("AGENTBOX_SKIP_RUNTIME_SYNC")
	if !ok {
		return false
	}

	switch strings.ToLower(value) {
	case "1", "true":
		return true
	default:
		return false
	}
}

func writeCommandOutput(cmd *cobra.Command, output []byte) error {
	_, err := cmd.OutOrStdout().Write(output)
	return err
}

func policyConfigError(args []string) error {
	if len(args) > 0 {
		return fmt.Errorf("agentbox policy config does not accept arguments")
	}

	return nil
}
