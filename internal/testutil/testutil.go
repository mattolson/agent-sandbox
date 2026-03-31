package testutil

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/cobra"
)

func MustMkdirAll(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
}

func WriteFile(t *testing.T, root string, relativePath string, content string) string {
	t.Helper()

	fullPath := filepath.Join(root, relativePath)
	MustMkdirAll(t, filepath.Dir(fullPath))
	if err := os.WriteFile(fullPath, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", fullPath, err)
	}

	return fullPath
}

func ExecuteCommand(cmd *cobra.Command, args ...string) (stdout string, stderr string, err error) {
	var stdoutBuf bytes.Buffer
	var stderrBuf bytes.Buffer

	cmd.SetOut(&stdoutBuf)
	cmd.SetErr(&stderrBuf)
	cmd.SetArgs(args)
	err = cmd.Execute()

	return stdoutBuf.String(), stderrBuf.String(), err
}
