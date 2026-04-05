package cli

import (
	"strings"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/testutil"
)

func TestInitRejectsInvalidAgentValue(t *testing.T) {
	repoRoot := t.TempDir()
	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, _, err := testutil.ExecuteCommand(cmd, "init", "--name", "my-project", "--agent", "invalid", "--path", repoRoot)
	if err == nil || err.Error() != "Invalid agent: invalid (expected: claude codex gemini opencode pi copilot factory)" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestInitRejectsInvalidModeValue(t *testing.T) {
	repoRoot := t.TempDir()
	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, _, err := testutil.ExecuteCommand(cmd, "init", "--name", "my-project", "--agent", "claude", "--mode", "invalid", "--path", repoRoot)
	if err == nil || err.Error() != "Invalid mode: invalid (expected: cli devcontainer)" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestInitRejectsInvalidIDEValue(t *testing.T) {
	repoRoot := t.TempDir()
	cmd := NewRootCommand(Options{WorkingDir: repoRoot})
	_, _, err := testutil.ExecuteCommand(cmd, "init", "--agent", "claude", "--mode", "devcontainer", "--ide", "invalid", "--name", "test", "--path", repoRoot)
	if err == nil || err.Error() != "Invalid IDE: invalid (expected: vscode jetbrains none)" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestInitFailsFastForLegacyLayoutsBeforePrompting(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/docker-compose.yml", "services: {}\n")
	prompter := &fakePrompter{}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Prompter: prompter})
	_, _, err := testutil.ExecuteCommand(cmd, "init", "--path", repoRoot)
	if err == nil {
		t.Fatal("expected legacy layout error")
	}
	if prompter.calls != 0 {
		t.Fatalf("expected no prompt calls, got %d", prompter.calls)
	}
	for _, snippet := range []string{"does not support the legacy single-file layout", ".agent-sandbox/docker-compose.legacy.yml", "docs/upgrades/m8-layered-layout.md"} {
		if !strings.Contains(err.Error(), snippet) {
			t.Fatalf("expected legacy error to contain %q, got %q", snippet, err.Error())
		}
	}
}

func TestInitAcceptsValidBatchCLIValuesAndWritesState(t *testing.T) {
	repoRoot := t.TempDir()
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, LookupEnv: mapLookup(map[string]string{
		"AGENTBOX_PROXY_IMAGE": "agent-sandbox-proxy:local",
		"AGENTBOX_AGENT_IMAGE": "agent-sandbox-claude:local",
	})})
	_, stderr, err := testutil.ExecuteCommand(cmd, "init", "--batch", "--agent", "claude", "--mode", "cli", "--name", "test", "--path", repoRoot)
	if err != nil {
		t.Fatalf("init failed: %v", err)
	}
	target, err := runtime.ReadActiveTarget(repoRoot)
	if err != nil {
		t.Fatalf("ReadActiveTarget failed: %v", err)
	}
	if target.ActiveAgent != "claude" || target.ProjectName != "test" {
		t.Fatalf("unexpected target state: %+v", target)
	}
	if !strings.Contains(stderr, "agentbox policy config") || !strings.Contains(stderr, "agentbox compose config") {
		t.Fatalf("expected view hint in stderr, got %q", stderr)
	}
}

func TestInitInteractiveDevcontainerFlowUsesPromptDefaultsAndWritesState(t *testing.T) {
	repoRoot := t.TempDir()
	prompter := &fakePrompter{
		readLineResponses: []string{""},
		selectResponses:   []string{"copilot", "devcontainer", "vscode"},
	}
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, Prompter: prompter, LookupEnv: mapLookup(map[string]string{
		"AGENTBOX_PROXY_IMAGE": "agent-sandbox-proxy:local",
		"AGENTBOX_AGENT_IMAGE": "agent-sandbox-copilot:local",
	})})
	_, _, err := testutil.ExecuteCommand(cmd, "init", "--path", repoRoot)
	if err != nil {
		t.Fatalf("init failed: %v", err)
	}
	target, err := runtime.ReadActiveTarget(repoRoot)
	if err != nil {
		t.Fatalf("ReadActiveTarget failed: %v", err)
	}
	if target.ActiveAgent != "copilot" || target.DevcontainerIDE != "vscode" || target.ProjectName != runtime.DeriveBaseProjectName(repoRoot) {
		t.Fatalf("unexpected target state: %+v", target)
	}
	if strings.Join(prompter.prompts, "\n") != strings.Join([]string{
		"Project name [" + runtime.DeriveBaseProjectName(repoRoot) + "]:",
		"Select agent:",
		"Select mode:",
		"Select IDE:",
	}, "\n") {
		t.Fatalf("unexpected prompts: %v", prompter.prompts)
	}
}

func TestInitCLIPropagatesMalformedExistingTargetState(t *testing.T) {
	repoRoot := t.TempDir()
	testutil.WriteFile(t, repoRoot, ".agent-sandbox/active-target.env", "not valid state\n")
	cmd := NewRootCommand(Options{WorkingDir: repoRoot, LookupEnv: mapLookup(map[string]string{
		"AGENTBOX_PROXY_IMAGE": "agent-sandbox-proxy:local",
		"AGENTBOX_AGENT_IMAGE": "agent-sandbox-claude:local",
	})})

	_, _, err := testutil.ExecuteCommand(cmd, "init", "--batch", "--agent", "claude", "--mode", "cli", "--name", "test", "--path", repoRoot)
	if err == nil {
		t.Fatal("expected malformed target state to fail")
	}
	if !strings.Contains(err.Error(), "parse target state line 1") {
		t.Fatalf("unexpected error: %v", err)
	}
}

type fakePrompter struct {
	readLineResponses []string
	selectResponses   []string
	prompts           []string
	calls             int
}

func (prompter *fakePrompter) ReadLine(prompt string) (string, error) {
	prompter.prompts = append(prompter.prompts, prompt)
	prompter.calls++
	response := prompter.readLineResponses[0]
	prompter.readLineResponses = prompter.readLineResponses[1:]
	return response, nil
}

func (prompter *fakePrompter) SelectOption(prompt string, _ []string) (string, error) {
	prompter.prompts = append(prompter.prompts, prompt)
	prompter.calls++
	response := prompter.selectResponses[0]
	prompter.selectResponses = prompter.selectResponses[1:]
	return response, nil
}

func mapLookup(values map[string]string) func(string) string {
	return func(key string) string {
		return values[key]
	}
}
