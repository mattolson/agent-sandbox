package scaffold

import (
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestWritePolicyFileCompactsServicesAndPreservesHeader(t *testing.T) {
	path := filepath.Join(t.TempDir(), "policy.yaml")

	if err := WritePolicyFile(path, "", "vscode", "", "github"); err != nil {
		t.Fatalf("WritePolicyFile failed: %v", err)
	}

	data := string(readFile(t, path))
	if !strings.HasPrefix(data, "# Agent sandbox network policy") {
		t.Fatalf("expected template header to be preserved, got %q", data)
	}
	if !strings.Contains(data, "services:\n  - vscode\n  - github\n") {
		t.Fatalf("expected two-space YAML indentation, got %q", data)
	}

	policy := readPolicy(t, path)
	want := []string{"vscode", "github"}
	if !reflect.DeepEqual(policy.Services, want) {
		t.Fatalf("unexpected services: got %v want %v", policy.Services, want)
	}
}
