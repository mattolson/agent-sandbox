package cli

import (
	"io"

	"github.com/mattolson/agent-sandbox/internal/version"
	"github.com/spf13/cobra"
)

type Options struct {
	Stdout  io.Writer
	Stderr  io.Writer
	Version version.Info
}

func NewRootCommand(opts Options) *cobra.Command {
	cmd := &cobra.Command{
		Use:           "agentbox",
		Short:         "Manage secure local agent sandboxes",
		SilenceErrors: true,
		SilenceUsage:  true,
	}

	if opts.Stdout != nil {
		cmd.SetOut(opts.Stdout)
	}
	if opts.Stderr != nil {
		cmd.SetErr(opts.Stderr)
	}

	cmd.AddCommand(
		newPendingLeafCommand("init", "Initialize a project sandbox"),
		newPendingLeafCommand("switch", "Switch the active agent"),
		newEditCommand(),
		newPolicyCommand(),
		newPendingLeafCommand("bump", "Refresh managed image digests"),
		newPendingLeafCommand("up", "Start the sandbox runtime"),
		newPendingLeafCommand("down", "Stop the sandbox runtime"),
		newPendingLeafCommand("logs", "Show runtime logs"),
		newPendingLeafCommand("compose", "Run docker compose against the sandbox stack"),
		newPendingLeafCommand("exec", "Open a shell in the sandbox container"),
		newPendingLeafCommand("destroy", "Remove sandbox files and resources"),
		newVersionCommand(opts.Version),
	)

	return cmd
}

func newEditCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "edit",
		Short: "Edit user-owned runtime configuration",
		RunE: func(cmd *cobra.Command, _ []string) error {
			return cmd.Help()
		},
	}

	cmd.AddCommand(
		newPendingLeafCommand("compose", "Edit compose overrides"),
		newPendingLeafCommand("policy", "Edit policy overrides"),
	)

	return cmd
}

func newPolicyCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "policy",
		Short: "Inspect rendered sandbox policy",
		RunE: func(cmd *cobra.Command, _ []string) error {
			return cmd.Help()
		},
	}

	cmd.AddCommand(
		newPendingLeafCommand("config", "Render the effective policy"),
		newPendingLeafCommand("render", "Alias for 'policy config' - deprecated"),
	)

	return cmd
}
