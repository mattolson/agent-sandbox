package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newPendingLeafCommand(use string, short string) *cobra.Command {
	cmd := &cobra.Command{
		Use:                use,
		Short:              short,
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return pendingPortError(cmd.CommandPath())
		},
	}

	return cmd
}

func pendingPortError(commandPath string) error {
	return fmt.Errorf("%s is not implemented in the Go CLI yet; use ./cli/bin/agentbox for now", commandPath)
}
