package scaffold

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// defaultSecretDirRelative is the default host secret directory below $HOME.
// It mirrors the default in proxySecretMountSource, which the base compose
// layer mounts read-only into the proxy.
const defaultSecretDirRelative = ".config/agent-sandbox/secrets"

// ensureDefaultSecretDir creates the default host secret directory when it is
// missing. The proxy mount sets create_host_path: false, so the proxy fails to
// start when the directory does not exist, and nothing in the quick start asks
// the user to create it.
//
// Only the default location is created, with mode 0700 as docs/secrets.md
// recommends. A custom AGENTBOX_SECRET_DIR is user-named, so a missing path
// there keeps failing loudly instead of turning a typo into an empty
// directory. HOME comes from the same lookup docker compose uses to expand
// ${HOME}; without it the default mount cannot resolve either, so there is
// nothing to create.
func ensureDefaultSecretDir(lookup func(string) string) error {
	if lookup == nil {
		lookup = os.Getenv
	}
	if lookup("AGENTBOX_SECRET_DIR") != "" {
		return nil
	}
	home := lookup("HOME")
	if home == "" {
		return nil
	}

	dir := filepath.Join(home, defaultSecretDirRelative)
	info, err := os.Stat(dir)
	if err == nil {
		if !info.IsDir() {
			return fmt.Errorf("default secret directory %s exists but is not a directory", dir)
		}
		return nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		return err
	}
	if err := os.Mkdir(dir, 0o700); err != nil {
		return err
	}

	// Mkdir applies the umask; make the recommended mode explicit.
	return os.Chmod(dir, 0o700)
}
