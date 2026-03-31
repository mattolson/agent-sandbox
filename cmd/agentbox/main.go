package main

import (
	"fmt"
	"os"

	"github.com/mattolson/agent-sandbox/internal/cli"
	"github.com/mattolson/agent-sandbox/internal/version"
)

func main() {
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	cmd := cli.NewRootCommand(cli.Options{
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Version: version.Detect(version.Options{
			WorkingDir: cwd,
		}),
	})

	if err := cmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
