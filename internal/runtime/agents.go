package runtime

import (
	"fmt"
	"slices"
	"strings"
)

var supportedAgents = []string{"claude", "codex", "gemini", "opencode", "pi", "copilot", "factory"}

func SupportedAgents() []string {
	return slices.Clone(supportedAgents)
}

func SupportedAgentsDisplay() string {
	return strings.Join(supportedAgents, " ")
}

func ValidateAgent(agent string) error {
	if slices.Contains(supportedAgents, agent) {
		return nil
	}

	return fmt.Errorf("invalid agent: %s (expected: %s)", agent, SupportedAgentsDisplay())
}
