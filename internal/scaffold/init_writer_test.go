package scaffold

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteFileIfChangedWritesViaTempFileAndLeavesNoTmp(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "managed.yml")

	if err := writeFileIfChanged(path, []byte("first\n"), 0o644); err != nil {
		t.Fatalf("writeFileIfChanged first write failed: %v", err)
	}
	assertFileContent(t, path, "first\n")
	assertPathMissing(t, path+".tmp")

	if err := writeFileIfChanged(path, []byte("second\n"), 0o644); err != nil {
		t.Fatalf("writeFileIfChanged rewrite failed: %v", err)
	}
	assertFileContent(t, path, "second\n")
	assertPathMissing(t, path+".tmp")
}

func TestWriteFileIfChangedSkipsIdenticalContent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "managed.yml")
	if err := os.WriteFile(path, []byte("stable\n"), 0o644); err != nil {
		t.Fatalf("seed file: %v", err)
	}

	if err := writeFileIfChanged(path, []byte("stable\n"), 0o644); err != nil {
		t.Fatalf("writeFileIfChanged failed: %v", err)
	}
	assertFileContent(t, path, "stable\n")
	assertPathMissing(t, path+".tmp")
}

func assertFileContent(t *testing.T, path string, want string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if string(data) != want {
		t.Fatalf("unexpected file content: got %q want %q", string(data), want)
	}
}

func assertPathMissing(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("expected %s to be absent, got %v", path, err)
	}
}
