package cli

import (
	"fmt"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/spf13/cobra"
)

func newProxyCommand(deps commandDeps) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "proxy",
		Short: "Interact with the proxy sidecar",
		RunE: func(cmd *cobra.Command, _ []string) error {
			return cmd.Help()
		},
	}

	cmd.AddCommand(newProxyReloadCommand(deps))

	return cmd
}

func newProxyReloadCommand(deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:   "reload",
		Short: "Reload proxy policy by sending SIGHUP",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			stack, err := resolveComposeStackForCommand(deps, "proxy reload")
			if err != nil {
				return err
			}

			if err := deps.runner.Run(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, "kill", "-s", "HUP", "proxy"), docker.CommandOptions{
				Dir:    stack.RepoRoot,
				Stdin:  cmd.InOrStdin(),
				Stdout: cmd.OutOrStdout(),
				Stderr: cmd.ErrOrStderr(),
			}); err != nil {
				return err
			}

			_, err = fmt.Fprintln(cmd.OutOrStdout(), "Sent SIGHUP to proxy. Check 'agentbox logs proxy' for the applied/rejected event.")
			return err
		},
	}
}
