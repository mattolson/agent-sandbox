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

type switchArgs struct {
	Agent string
}

func newSwitchCommand(opts Options, deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                "switch",
		Short:              "Switch the active agent",
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			parsed, err := parseSwitchArgs(args)
			if err != nil {
				return err
			}

			repoRoot, err := runtime.FindRepoRoot(deps.workingDir)
			if err != nil {
				return err
			}
			if !runtime.AgentSandboxInitialized(repoRoot) {
				return fmt.Errorf("agent-sandbox is not initialized at %s. Run 'agentbox init' first.", repoRoot)
			}
			if parsed.Agent != "" {
				if err := runtime.ValidateAgent(parsed.Agent); err != nil {
					return err
				}
			}
			if err := runtime.AbortIfUnsupportedLegacyLayout(repoRoot, "switch", parsed.Agent, "", ""); err != nil {
				return err
			}

			agent := parsed.Agent
			if agent == "" {
				agent, err = commandPrompter(cmd, opts.Prompter).SelectOption("Select agent:", runtime.SupportedAgents())
				if err != nil {
					return err
				}
			}

			currentTarget, err := currentTargetIfExists(repoRoot)
			if err != nil {
				return err
			}
			layout, hasManagedLayout := runtime.PreferredManagedLayout(repoRoot)

			if currentTarget.ActiveAgent == agent {
				refreshed := false
				switch layout {
				case runtime.LayoutCentralizedDevcontainer:
					if _, err := scaffold.EnsureDevcontainerRuntimeFiles(cmd.Context(), scaffold.SyncParams{
						RepoRoot:  repoRoot,
						Agent:     agent,
						Runner:    deps.runner,
						Stderr:    cmd.ErrOrStderr(),
						LookupEnv: opts.LookupEnv,
					}); err != nil {
						return err
					}
					refreshed = true
				case runtime.LayoutLayeredCLI:
					if _, err := scaffold.EnsureCLIAgentRuntimeFiles(cmd.Context(), scaffold.SyncParams{
						RepoRoot:  repoRoot,
						Agent:     agent,
						Runner:    deps.runner,
						Stderr:    cmd.ErrOrStderr(),
						LookupEnv: opts.LookupEnv,
					}); err != nil {
						return err
					}
					refreshed = true
				}

				if refreshed {
					_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Active agent is already '%s'. Refreshed layered runtime files.\n", agent)
				} else {
					_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Active agent is already '%s'. No changes made.\n", agent)
				}
				return nil
			}

			runtimeRunning := false
			var currentStack runtime.ComposeStack
			if currentTarget.ActiveAgent != "" && hasManagedLayout {
				currentStack, err = composeStackForLayout(repoRoot, layout, currentTarget)
				if err == nil {
					output, outputErr := deps.runner.Output(cmd.Context(), "docker", docker.ComposeArgs(currentStack.Files, "ps", "--status", "running", "--quiet"), docker.CommandOptions{
						Dir:    repoRoot,
						Stderr: io.Discard,
					})
					if outputErr == nil && strings.TrimSpace(string(output)) != "" {
						runtimeRunning = true
					}
				}
			}

			updatedTarget := currentTarget
			updatedTarget.ActiveAgent = agent
			switch layout {
			case runtime.LayoutCentralizedDevcontainer:
				updatedTarget, err = scaffold.EnsureDevcontainerRuntimeFiles(cmd.Context(), scaffold.SyncParams{
					RepoRoot:  repoRoot,
					Agent:     agent,
					Runner:    deps.runner,
					Stderr:    cmd.ErrOrStderr(),
					LookupEnv: opts.LookupEnv,
				})
				if err != nil {
					return err
				}
			case runtime.LayoutLayeredCLI:
				updatedTarget, err = scaffold.EnsureCLIAgentRuntimeFiles(cmd.Context(), scaffold.SyncParams{
					RepoRoot:  repoRoot,
					Agent:     agent,
					Runner:    deps.runner,
					Stderr:    cmd.ErrOrStderr(),
					LookupEnv: opts.LookupEnv,
				})
				if err != nil {
					return err
				}
			}

			if runtimeRunning {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Active agent set to '%s'. Restarting containers to apply the switch...\n", agent)
				if err := runComposeCommand(cmd.Context(), deps.runner, currentStack, cmd, "down"); err != nil {
					return err
				}
				if err := runtime.WriteTargetState(repoRoot, updatedTarget); err != nil {
					return err
				}
				targetStack, err := composeStackForLayout(repoRoot, layout, updatedTarget)
				if err != nil {
					return err
				}
				return runComposeCommand(cmd.Context(), deps.runner, targetStack, cmd, "up", "-d")
			}

			if err := runtime.WriteTargetState(repoRoot, updatedTarget); err != nil {
				return err
			}
			_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Active agent set to '%s'.\n", agent)
			return nil
		},
	}
}

func parseSwitchArgs(args []string) (switchArgs, error) {
	parsed := switchArgs{}
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--agent":
			if i+1 >= len(args) {
				return switchArgs{}, fmt.Errorf("Missing value for --agent")
			}
			parsed.Agent = args[i+1]
			i++
		default:
			return switchArgs{}, fmt.Errorf("Unknown option: %s", args[i])
		}
	}

	return parsed, nil
}
