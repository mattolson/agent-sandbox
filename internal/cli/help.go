package cli

import "github.com/spf13/cobra"

func showHelpIfRequested(cmd *cobra.Command, args []string) (bool, error) {
	for _, arg := range args {
		if isHelpFlag(arg) {
			return true, cmd.Help()
		}
	}
	return false, nil
}

func showHelpIfOnlyArg(cmd *cobra.Command, args []string) (bool, error) {
	if len(args) == 1 && isHelpFlag(args[0]) {
		return true, cmd.Help()
	}
	return false, nil
}

func isHelpFlag(arg string) bool {
	return arg == "-h" || arg == "--help"
}
