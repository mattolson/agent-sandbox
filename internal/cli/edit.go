package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/scaffold"
	"github.com/spf13/cobra"
)

// editComposeArgs captures flags for edit compose.
type editComposeArgs struct {
	NoRestart bool
}

// editPolicyArgs captures flags for edit policy.
type editPolicyArgs struct {
	Mode  string
	Agent string
}

func newEditCommand(opts Options, deps commandDeps) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "edit",
		Short: "Edit user-owned runtime configuration",
		RunE: func(cmd *cobra.Command, _ []string) error {
			return cmd.Help()
		},
	}

	cmd.AddCommand(
		newEditComposeCommand(opts, deps),
		newEditPolicyCommand(opts, deps),
	)

	return cmd
}

func newEditComposeCommand(opts Options, deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                "compose",
		Short:              "Edit compose overrides",
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			parsed, err := parseEditComposeArgs(args)
			if err != nil {
				return err
			}

			repoRoot, err := runtime.FindRepoRoot(deps.workingDir)
			if err != nil {
				return err
			}
			if err := runtime.AbortIfUnsupportedLegacyLayout(repoRoot, "edit compose", "", "", ""); err != nil {
				return err
			}
			if _, ok := runtime.PreferredManagedLayout(repoRoot); !ok {
				return fmt.Errorf("No layered compose layout found at %s. Run 'agentbox init' first.", repoRoot)
			}
			if err := scaffold.EnsureSharedComposeOverride(repoRoot, opts.LookupEnv); err != nil {
				return err
			}

			editor, err := resolveEditorFromLookup(opts.LookupEnv)
			if err != nil {
				return err
			}
			composeFile := runtime.CLIUserOverrideFile(repoRoot)
			before, err := statFile(composeFile)
			if err != nil {
				return err
			}
			if err := runEditor(cmd.Context(), cmd, editor, composeFile); err != nil {
				return err
			}
			after, err := statFile(composeFile)
			if err != nil {
				return err
			}

			if !fileChanged(before, after) {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "No changes detected.")
				return nil
			}

			stack, err := runtime.ResolveComposeStack(repoRoot)
			if err != nil {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Compose file was modified.")
				return nil
			}
			output, err := deps.runner.Output(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, "ps", "--status", "running", "--quiet"), docker.CommandOptions{
				Dir:    repoRoot,
				Stderr: io.Discard,
			})
			running := err == nil && strings.TrimSpace(string(output)) != ""
			if !running {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Compose file was modified.")
				return nil
			}

			if parsed.NoRestart || envTrue(opts.LookupEnv, "AGENTBOX_NO_RESTART") {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Compose file was modified, and you have containers running.")
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "To pick up the changes and restart your containers, run: agentbox up -d")
				return nil
			}

			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Compose file was modified. Restarting containers...")
			if runtime.ComposeCommandRequiresRuntimeSync("up", shouldSkipRuntimeSync()) {
				if err := deps.syncer.Sync(cmd.Context(), stack); err != nil {
					return err
				}
				stack, err = runtime.ResolveComposeStack(repoRoot)
				if err != nil {
					return err
				}
			}
			return runComposeCommand(cmd.Context(), deps.runner, stack, cmd, "up", "-d")
		},
	}
}

func newEditPolicyCommand(opts Options, deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                "policy",
		Short:              "Edit policy overrides",
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			parsed, err := parseEditPolicyArgs(args)
			if err != nil {
				return err
			}

			repoRoot, err := runtime.FindRepoRoot(deps.workingDir)
			if err != nil {
				return err
			}
			if parsed.Agent != "" {
				if err := runtime.ValidateAgent(parsed.Agent); err != nil {
					return err
				}
			}
			if parsed.Mode != "" && parsed.Mode != runtime.ModeCLI && parsed.Mode != runtime.ModeDevcontainer {
				return fmt.Errorf("Invalid mode: %s (expected: cli devcontainer)", parsed.Mode)
			}
			if err := runtime.AbortIfUnsupportedLegacyLayout(repoRoot, "edit policy", parsed.Agent, parsed.Mode, ""); err != nil {
				return err
			}
			if _, ok := runtime.PreferredManagedLayout(repoRoot); !ok {
				return fmt.Errorf("No layered policy layout found at %s. Run 'agentbox init' first.", repoRoot)
			}

			policyFile := runtime.SharedPolicyFile(repoRoot)
			restartScope := "active"
			if parsed.Agent != "" {
				if err := scaffold.EnsureAgentPolicyFile(repoRoot, parsed.Agent); err != nil {
					return err
				}
				policyFile = runtime.UserAgentPolicyFile(repoRoot, parsed.Agent)
				currentTarget, err := currentTargetIfExists(repoRoot)
				if err != nil {
					return err
				}
				if currentTarget.ActiveAgent != "" && currentTarget.ActiveAgent != parsed.Agent {
					restartScope = "inactive-agent"
				}
			} else if err := scaffold.EnsureSharedPolicyFile(repoRoot); err != nil {
				return err
			}

			editor, err := resolveEditorFromLookup(opts.LookupEnv)
			if err != nil {
				return err
			}
			before, err := statFile(policyFile)
			if err != nil {
				return err
			}
			if err := runEditor(cmd.Context(), cmd, editor, policyFile); err != nil {
				return err
			}
			after, err := statFile(policyFile)
			if err != nil {
				return err
			}

			if !fileChanged(before, after) {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Policy file unchanged. Skipping reload.")
				return nil
			}
			if restartScope == "inactive-agent" {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Policy file was modified for inactive agent '%s'. Changes apply after 'agentbox switch --agent %s'.\n", parsed.Agent, parsed.Agent)
				return nil
			}

			stack, err := runtime.ResolveComposeStack(repoRoot)
			if err != nil {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Policy file was modified, but proxy service is not running. Skipping reload.")
				return nil
			}
			output, err := deps.runner.Output(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, "ps", "proxy", "--status", "running", "--quiet"), docker.CommandOptions{
				Dir:    repoRoot,
				Stderr: io.Discard,
			})
			if err != nil || strings.TrimSpace(string(output)) == "" {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Policy file was modified, but proxy service is not running. Skipping reload.")
				return nil
			}

			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Policy file was modified. Reloading proxy policy...")
			return runComposeCommand(cmd.Context(), deps.runner, stack, cmd, "kill", "-s", "HUP", "proxy")
		},
	}
}

func parseEditComposeArgs(args []string) (editComposeArgs, error) {
	parsed := editComposeArgs{}
	for _, arg := range args {
		switch arg {
		case "--no-restart":
			parsed.NoRestart = true
		default:
			return editComposeArgs{}, fmt.Errorf("Unknown option: %s", arg)
		}
	}

	return parsed, nil
}

func parseEditPolicyArgs(args []string) (editPolicyArgs, error) {
	parsed := editPolicyArgs{}
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--mode":
			if i+1 >= len(args) {
				return editPolicyArgs{}, fmt.Errorf("Missing value for --mode")
			}
			parsed.Mode = args[i+1]
			i++
		case "--agent":
			if i+1 >= len(args) {
				return editPolicyArgs{}, fmt.Errorf("Missing value for --agent")
			}
			parsed.Agent = args[i+1]
			i++
		default:
			return editPolicyArgs{}, fmt.Errorf("Unknown argument: %s", args[i])
		}
	}

	return parsed, nil
}
