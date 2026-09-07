package scaffold

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestInitializeCLICreatesDefaultSecretDir(t *testing.T) {
	home := t.TempDir()
	initializeCLIWithHome(t, home, nil)

	assertSecretDir(t, filepath.Join(home, ".config", "agent-sandbox", "secrets"), 0o700)
}

func TestInitializeCLILeavesCustomSecretDirAlone(t *testing.T) {
	home := t.TempDir()
	custom := filepath.Join(t.TempDir(), "custom-secrets")
	initializeCLIWithHome(t, home, map[string]string{"AGENTBOX_SECRET_DIR": custom})

	assertPathMissing(t, filepath.Join(home, ".config", "agent-sandbox", "secrets"))
	assertPathMissing(t, custom)
}

func TestInitializeCLIPreservesExistingSecretDirMode(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, ".config", "agent-sandbox", "secrets")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatalf("chmod: %v", err)
	}
	initializeCLIWithHome(t, home, nil)

	assertSecretDir(t, dir, 0o755)
}

func TestInitializeCLIRejectsSecretPathThatIsNotADirectory(t *testing.T) {
	home := t.TempDir()
	path := filepath.Join(home, ".config", "agent-sandbox", "secrets")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(path, []byte("not a directory\n"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}

	err := InitializeCLI(context.Background(), InitParams{
		RepoRoot:    t.TempDir(),
		Agent:       "claude",
		ProjectName: "project-sandbox",
		LookupEnv:   mapLookup(secretDirEnv(home, nil)),
	})
	if err == nil || !strings.Contains(err.Error(), "not a directory") {
		t.Fatalf("expected not-a-directory error, got %v", err)
	}
}

func TestEnsureCLIAgentRuntimeFilesCreatesDefaultSecretDir(t *testing.T) {
	repoRoot := t.TempDir()
	home := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "ACTIVE_AGENT=claude\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/base.yml", "services:\n  proxy:\n    image: agent-sandbox-proxy:local\n")
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/compose/agent.claude.yml", "services:\n  agent:\n    image: agent-sandbox-claude:local\n")

	if _, err := EnsureCLIAgentRuntimeFiles(context.Background(), SyncParams{
		RepoRoot:  repoRoot,
		Agent:     "claude",
		LookupEnv: mapLookup(map[string]string{"HOME": home}),
	}); err != nil {
		t.Fatalf("EnsureCLIAgentRuntimeFiles failed: %v", err)
	}

	assertSecretDir(t, filepath.Join(home, ".config", "agent-sandbox", "secrets"), 0o700)
}

func TestEnsureDefaultSecretDirSkipsWithoutHome(t *testing.T) {
	if err := ensureDefaultSecretDir(mapLookup(map[string]string{})); err != nil {
		t.Fatalf("expected no error without HOME, got %v", err)
	}
}

func initializeCLIWithHome(t *testing.T, home string, extra map[string]string) {
	t.Helper()
	if err := InitializeCLI(context.Background(), InitParams{
		RepoRoot:    t.TempDir(),
		Agent:       "claude",
		ProjectName: "project-sandbox",
		LookupEnv:   mapLookup(secretDirEnv(home, extra)),
	}); err != nil {
		t.Fatalf("InitializeCLI failed: %v", err)
	}
}

func secretDirEnv(home string, extra map[string]string) map[string]string {
	env := map[string]string{
		"HOME":                 home,
		"AGENTBOX_PROXY_IMAGE": "agent-sandbox-proxy:local",
		"AGENTBOX_AGENT_IMAGE": "agent-sandbox-claude:local",
	}
	for key, value := range extra {
		env[key] = value
	}
	return env
}

func assertSecretDir(t *testing.T, path string, mode os.FileMode) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("expected secret directory %s to exist: %v", path, err)
	}
	if !info.IsDir() {
		t.Fatalf("expected %s to be a directory", path)
	}
	if got := info.Mode().Perm(); got != mode {
		t.Fatalf("unexpected mode for %s: got %o want %o", path, got, mode)
	}
}

func TestCreateSecretDirToleratesConcurrentCreation(t *testing.T) {
	dir := filepath.Join(t.TempDir(), ".config", "agent-sandbox", "secrets")

	const workers = 8
	errs := make(chan error, workers)
	var start, done sync.WaitGroup
	start.Add(1)
	done.Add(workers)
	for i := 0; i < workers; i++ {
		go func() {
			defer done.Done()
			start.Wait()
			errs <- createSecretDir(dir)
		}()
	}
	start.Done()
	done.Wait()
	close(errs)

	for err := range errs {
		if err != nil {
			t.Fatalf("concurrent createSecretDir failed: %v", err)
		}
	}
	assertSecretDir(t, dir, 0o700)
}
