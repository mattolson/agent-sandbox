package cli

import (
	"fmt"

	"github.com/mattolson/agent-sandbox/internal/version"
	"github.com/spf13/cobra"
)

func newVersionCommand(info version.Info) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version metadata",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			_, err := fmt.Fprintln(cmd.OutOrStdout(), info.Format("Agent Sandbox"))
			return err
		},
	}
}
