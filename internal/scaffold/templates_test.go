package scaffold

import (
	"strings"
	"testing"
)

func TestReadTemplateLoadsEmbeddedTemplate(t *testing.T) {
	data, err := ReadTemplate("compose/base.yml")
	if err != nil {
		t.Fatalf("ReadTemplate failed: %v", err)
	}
	if !strings.Contains(string(data), "Managed by agentbox") {
		t.Fatalf("unexpected template contents: %q", string(data))
	}
}

func TestReadTemplateLoadsNestedAgentTemplate(t *testing.T) {
	data, err := ReadTemplate("opencode/cli/agent.yml")
	if err != nil {
		t.Fatalf("ReadTemplate failed: %v", err)
	}
	if !strings.Contains(string(data), "agent-sandbox-opencode") {
		t.Fatalf("unexpected nested template contents: %q", string(data))
	}
}
