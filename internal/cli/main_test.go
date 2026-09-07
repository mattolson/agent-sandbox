package cli

import (
	"os"
	"testing"
)

// TestMain points HOME at a scratch directory so scaffold code that creates
// host-side directories, such as the default secret directory, never touches
// the developer's real home directory during tests.
func TestMain(m *testing.M) {
	home, err := os.MkdirTemp("", "agentbox-test-home-")
	if err != nil {
		panic(err)
	}
	os.Setenv("HOME", home)
	code := m.Run()
	os.RemoveAll(home)
	os.Exit(code)
}
