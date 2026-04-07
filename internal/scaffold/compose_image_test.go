package scaffold

import (
	"os"
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestSetComposeServiceImagePreservesHeaderAndUpdatesService(t *testing.T) {
	path := testutil.WriteFile(t, t.TempDir(), "compose.yml", "# Managed by agentbox\n\nservices:\n  proxy:\n    image: ghcr.io/example/proxy:latest\n")

	changed, err := SetComposeServiceImage(path, "proxy", "ghcr.io/example/proxy@sha256:abc123")
	if err != nil {
		t.Fatalf("SetComposeServiceImage failed: %v", err)
	}
	if !changed {
		t.Fatal("expected image change")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if !strings.HasPrefix(string(data), "# Managed by agentbox\n\n") {
		t.Fatalf("expected header to be preserved, got %q", string(data))
	}
	if !strings.Contains(string(data), "services:\n  proxy:\n    image: ghcr.io/example/proxy@sha256:abc123\n") {
		t.Fatalf("expected updated image, got %q", string(data))
	}
}

func TestReadComposeServiceImageReturnsEmptyForMissingServiceImage(t *testing.T) {
	path := testutil.WriteFile(t, t.TempDir(), "compose.yml", "services:\n  proxy: {}\n")

	image, err := ReadComposeServiceImage(path, "proxy")
	if err != nil {
		t.Fatalf("ReadComposeServiceImage failed: %v", err)
	}
	if image != "" {
		t.Fatalf("expected empty image, got %q", image)
	}
}

func TestSetComposeServiceImagePreservesBlankNamedVolumeEntries(t *testing.T) {
	path := testutil.WriteFile(t, t.TempDir(), "compose.yml", "services:\n  proxy:\n    image: ghcr.io/example/proxy:latest\nvolumes:\n  claude-state:\n  claude-history:\n")

	changed, err := SetComposeServiceImage(path, "proxy", "ghcr.io/example/proxy@sha256:abc123")
	if err != nil {
		t.Fatalf("SetComposeServiceImage failed: %v", err)
	}
	if !changed {
		t.Fatal("expected image change")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	body := string(data)
	if strings.Contains(body, ": null") {
		t.Fatalf("expected blank named volume entries, got %q", body)
	}
	if !strings.Contains(body, "volumes:\n  claude-state:\n  claude-history:\n") {
		t.Fatalf("expected named volumes to stay blank and ordered, got %q", body)
	}
}
