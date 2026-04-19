package cli

import (
	"io"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/version"
	"github.com/spf13/cobra"
)

// Options configures the root CLI command and its shared dependencies.
type Options struct {
	Stdout        io.Writer
	Stderr        io.Writer
	Stdin         io.Reader
	WorkingDir    string
	Version       version.Info
	Runner        docker.Runner
	RuntimeSyncer RuntimeSyncer
	Prompter      Prompter
	LookupEnv     func(string) string
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
		newInitCommand(opts, deps),
		newSwitchCommand(opts, deps),
		newEditCommand(opts, deps),
		newPolicyCommand(deps),
		newProxyCommand(deps),
		newBumpCommand(deps),
		newRuntimeComposeCommand("up", "Start the sandbox runtime", "up", []string{"up"}, deps),
		newRuntimeComposeCommand("down", "Stop the sandbox runtime", "down", []string{"down"}, deps),
		newRuntimeComposeCommand("logs", "Show runtime logs", "logs", []string{"logs"}, deps),
		newRuntimeComposeCommand("compose", "Run docker compose against the sandbox stack", "compose", nil, deps),
		newExecCommand(deps),
		newDestroyCommand(opts, deps),
		newVersionCommand(opts.Version),
	)

	return cmd
}
