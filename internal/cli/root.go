package cli

import (
	"io"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/version"
	"github.com/spf13/cobra"
)

type Options struct {
	Stdout        io.Writer
	Stderr        io.Writer
	Stdin         io.Reader
	WorkingDir    string
	Version       version.Info
	Runner        docker.Runner
	RuntimeSyncer RuntimeSyncer
}

func NewRootCommand(opts Options) *cobra.Command {
	deps := newCommandDeps(opts)

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
	if opts.Stdin != nil {
		cmd.SetIn(opts.Stdin)
	}

	cmd.AddCommand(
		newPendingLeafCommand("init", "Initialize a project sandbox"),
		newPendingLeafCommand("switch", "Switch the active agent"),
		newEditCommand(),
		newPolicyCommand(deps),
		newPendingLeafCommand("bump", "Refresh managed image digests"),
		newRuntimeComposeCommand("up", "Start the sandbox runtime", "up", []string{"up"}, deps),
		newRuntimeComposeCommand("down", "Stop the sandbox runtime", "down", []string{"down"}, deps),
		newRuntimeComposeCommand("logs", "Show runtime logs", "logs", []string{"logs"}, deps),
		newRuntimeComposeCommand("compose", "Run docker compose against the sandbox stack", "compose", nil, deps),
		newExecCommand(deps),
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
