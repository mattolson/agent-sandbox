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
	if !strings.Contains(string(data), "ghcr.io/example/proxy@sha256:abc123") {
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
