package runtime

import (
	"strings"
	"testing"
)

func TestSupportedAgentsOrder(t *testing.T) {
	want := "claude,codex,gemini,opencode,pi,copilot,factory"
	got := strings.Join(SupportedAgents(), ",")
	if got != want {
		t.Fatalf("unexpected agent order: got %q want %q", got, want)
	}
}

func TestValidateAgent(t *testing.T) {
	if err := ValidateAgent("opencode"); err != nil {
		t.Fatalf("expected opencode to be valid: %v", err)
	}

	if err := ValidateAgent("unknown"); err == nil {
		t.Fatal("expected invalid agent to fail")
	}
}
