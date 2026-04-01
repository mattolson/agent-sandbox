package cli

import (
	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/spf13/cobra"
)

func newPolicyCommand(deps commandDeps) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "policy",
		Short: "Inspect rendered sandbox policy",
		RunE: func(cmd *cobra.Command, _ []string) error {
			return cmd.Help()
		},
	}

	cmd.AddCommand(
		newPolicyConfigCommand(deps),
		newPolicyRenderCommand(deps),
	)

	return cmd
}

func newPolicyConfigCommand(deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:   "config",
		Short: "Render the effective policy",
		Args:  cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := policyConfigError(args); err != nil {
				return err
			}

			stack, err := resolveComposeStackForCommand(deps, "policy config")
			if err != nil {
				return err
			}

			output, err := deps.runner.Output(cmd.Context(), "docker", docker.ComposeArgs(stack.Files, "run", "--rm", "--no-deps", "-T", "--entrypoint", "/usr/local/bin/render-policy", "proxy"), docker.CommandOptions{
				Dir:    stack.RepoRoot,
				Stderr: cmd.ErrOrStderr(),
			})
			if err != nil {
				return err
			}

			return writeCommandOutput(cmd, output)
		},
	}
}

func newPolicyRenderCommand(deps commandDeps) *cobra.Command {
	configCommand := newPolicyConfigCommand(deps)
	return &cobra.Command{
		Use:   "render",
		Short: "Alias for 'policy config' - deprecated",
		Args:  cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return configCommand.RunE(cmd, args)
		},
	}
}
