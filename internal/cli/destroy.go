package cli

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/spf13/cobra"
)

type destroyArgs struct {
	Force bool
}

func newDestroyCommand(opts Options, deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                "destroy",
		Short:              "Remove sandbox files and resources",
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			parsed, err := parseDestroyArgs(args)
			if err != nil {
				return err
			}

			repoRoot, err := runtime.FindRepoRoot(deps.workingDir)
			if err != nil {
				return err
			}

			if !parsed.Force {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "This will stop containers, remove volumes, and delete .devcontainer and %s directories.\n", runtime.AgentSandboxDirName)
				confirmed, err := promptYesNo(commandPrompter(cmd, opts.Prompter), "Continue?", false)
				if err != nil {
					return err
				}
				if !confirmed {
					_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Aborting")
					return nil
				}
			}

			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Stopping containers")
			shutdownDestroyRuntime(cmd, deps, repoRoot)

			projectDir := filepath.Join(repoRoot, runtime.AgentSandboxDirName)
			if info, err := os.Stat(projectDir); err == nil && info.IsDir() {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Removing %s\n", projectDir)
				if err := os.RemoveAll(projectDir); err != nil {
					return err
				}
			}

			devcontainerDir := filepath.Join(repoRoot, ".devcontainer")
			if info, err := os.Stat(devcontainerDir); err == nil && info.IsDir() {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Removing %s\n", devcontainerDir)
				if err := os.RemoveAll(devcontainerDir); err != nil {
					return err
				}
			}

			return nil
		},
	}
}

func parseDestroyArgs(args []string) (destroyArgs, error) {
	parsed := destroyArgs{}
	for _, arg := range args {
		switch arg {
		case "-f", "--force":
			parsed.Force = true
		default:
			return destroyArgs{}, fmt.Errorf("unknown parameter: %s", arg)
		}
	}

	return parsed, nil
}

func shutdownDestroyRuntime(cmd *cobra.Command, deps commandDeps, repoRoot string) {
	if _, ok := runtime.PreferredManagedLayout(repoRoot); ok {
		stack, err := runtime.ResolveComposeStack(repoRoot)
		if err != nil {
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Could not stop containers from the current compose layout. Continuing with filesystem cleanup.")
			return
		}
		if err := runComposeCommand(cmd.Context(), deps.runner, stack, cmd, "down", "--volumes"); err != nil {
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Could not stop containers from the current compose layout. Continuing with filesystem cleanup.")
		}
		return
	}

	legacyComposeFile, ok := runtime.LegacyDestroyComposeFile(repoRoot)
	if !ok {
		_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "No compose stack found. Skipping container shutdown.")
		return
	}
	if err := deps.runner.Run(cmd.Context(), "docker", docker.ComposeArgs([]string{legacyComposeFile}, "down", "--volumes"), docker.CommandOptions{
		Dir:    repoRoot,
		Stdin:  cmd.InOrStdin(),
		Stdout: cmd.OutOrStdout(),
		Stderr: cmd.ErrOrStderr(),
	}); err != nil {
		_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Could not stop containers from the legacy compose layout. Continuing with filesystem cleanup.")
	}
}
