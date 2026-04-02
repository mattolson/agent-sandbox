package scaffold

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"gopkg.in/yaml.v3"
)

func TestInitializeCLIWritesRepresentativeClaudeScaffold(t *testing.T) {
	repoRoot := t.TempDir()
	env := map[string]string{
		"AGENTBOX_PROXY_IMAGE":                 "agent-sandbox-proxy:local",
		"AGENTBOX_AGENT_IMAGE":                 "agent-sandbox-claude:local",
		"AGENTBOX_MOUNT_CLAUDE_CONFIG":         "true",
		"AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS": "true",
		"AGENTBOX_ENABLE_DOTFILES":             "true",
		"AGENTBOX_MOUNT_GIT_READONLY":          "true",
		"AGENTBOX_MOUNT_IDEA_READONLY":         "true",
		"AGENTBOX_MOUNT_VSCODE_READONLY":       "true",
	}

	if err := InitializeCLI(context.Background(), InitParams{
		RepoRoot:    repoRoot,
		Agent:       "claude",
		ProjectName: "project-sandbox",
		LookupEnv:   mapLookup(env),
	}); err != nil {
		t.Fatalf("InitializeCLI failed: %v", err)
	}

	base := readCompose(t, runtime.CLIBaseComposeFile(repoRoot))
	if base.Name != "project-sandbox" {
		t.Fatalf("unexpected project name: %q", base.Name)
	}
	assertContains(t, base.Services.Proxy.Volumes, "../policy/user.policy.yaml:/etc/agent-sandbox/policy/user.policy.yaml:ro")
	if base.Services.Proxy.Image != "agent-sandbox-proxy:local" {
		t.Fatalf("unexpected proxy image: %q", base.Services.Proxy.Image)
	}

	agent := readCompose(t, runtime.CLIAgentComposeFile(repoRoot, "claude"))
	if agent.Services.Agent.Image != "agent-sandbox-claude:local" {
		t.Fatalf("unexpected agent image: %q", agent.Services.Agent.Image)
	}
	assertContains(t, agent.Services.Proxy.Volumes, "../policy/user.agent.claude.policy.yaml:/etc/agent-sandbox/policy/user.agent.policy.yaml:ro")
	assertContains(t, agent.Services.Proxy.Environment, "AGENTBOX_ACTIVE_AGENT=claude")
	assertContains(t, agent.Services.Agent.Volumes, "claude-state:/home/dev/.claude")
	assertContains(t, agent.Services.Agent.Volumes, "claude-history:/commandhistory")

	sharedOverride := readCompose(t, runtime.CLIUserOverrideFile(repoRoot))
	for _, volume := range []string{
		`${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro`,
		`${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro`,
		`../../.git:/workspace/.git:ro`,
		`../../.idea:/workspace/.idea:ro`,
		`../../.vscode:/workspace/.vscode:ro`,
	} {
		assertContains(t, sharedOverride.Services.Agent.Volumes, volume)
	}

	agentOverride := readCompose(t, runtime.CLIUserAgentOverrideFile(repoRoot, "claude"))
	assertContains(t, agentOverride.Services.Agent.Volumes, `${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro`)
	assertContains(t, agentOverride.Services.Agent.Volumes, `${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro`)

	assertFileExists(t, runtime.SharedPolicyFile(repoRoot))
	assertFileExists(t, runtime.UserAgentPolicyFile(repoRoot, "claude"))
}

func TestInitializeDevcontainerWritesRepresentativeCodexScaffold(t *testing.T) {
	repoRoot := t.TempDir()
	env := map[string]string{
		"AGENTBOX_PROXY_IMAGE":                 "agent-sandbox-proxy:local",
		"AGENTBOX_AGENT_IMAGE":                 "agent-sandbox-codex:local",
		"AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS": "true",
		"AGENTBOX_ENABLE_DOTFILES":             "true",
		"AGENTBOX_MOUNT_GIT_READONLY":          "true",
		"AGENTBOX_MOUNT_IDEA_READONLY":         "true",
		"AGENTBOX_MOUNT_VSCODE_READONLY":       "true",
	}

	if err := InitializeDevcontainer(context.Background(), InitParams{
		RepoRoot:    repoRoot,
		Agent:       "codex",
		ProjectName: "project-sandbox",
		IDE:         "vscode",
		LookupEnv:   mapLookup(env),
	}); err != nil {
		t.Fatalf("InitializeDevcontainer failed: %v", err)
	}

	modeFile := readCompose(t, runtime.CLIDevcontainerModeComposeFile(repoRoot))
	if modeFile.Name != "project-sandbox-devcontainer" {
		t.Fatalf("unexpected mode project name: %q", modeFile.Name)
	}
	assertContains(t, modeFile.Services.Proxy.Volumes, "../policy/policy.devcontainer.yaml:/etc/agent-sandbox/policy/devcontainer.policy.yaml:ro")
	assertContains(t, modeFile.Services.Agent.Volumes, "../../.devcontainer:/workspace/.devcontainer:ro")
	assertContains(t, modeFile.Services.Agent.Volumes, "../../.vscode:/workspace/.vscode:ro")
	assertNotContains(t, modeFile.Services.Agent.Volumes, "../../.idea:/workspace/.idea:ro")

	sharedOverride := readCompose(t, runtime.CLIUserOverrideFile(repoRoot))
	assertNotContains(t, sharedOverride.Services.Agent.Volumes, "../../.idea:/workspace/.idea:ro")
	assertNotContains(t, sharedOverride.Services.Agent.Volumes, "../../.vscode:/workspace/.vscode:ro")
	assertContains(t, sharedOverride.Services.Agent.Volumes, `${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro`)

	devcontainerJSON := readJSONMap(t, filepath.Join(repoRoot, ".devcontainer", "devcontainer.json"))
	dockerComposeFiles := devcontainerJSON["dockerComposeFile"].([]any)
	if len(dockerComposeFiles) != 5 {
		t.Fatalf("unexpected dockerComposeFile count: %d", len(dockerComposeFiles))
	}
	if dockerComposeFiles[0].(string) != "../.agent-sandbox/compose/base.yml" {
		t.Fatalf("unexpected first compose file: %v", dockerComposeFiles[0])
	}
	if devcontainerJSON["service"].(string) != "agent" {
		t.Fatalf("unexpected service: %v", devcontainerJSON["service"])
	}

	policy := readPolicy(t, runtime.DevcontainerManagedPolicyFile(repoRoot))
	if len(policy.Services) != 1 || policy.Services[0] != "vscode" {
		t.Fatalf("unexpected policy services: %v", policy.Services)
	}
	assertFileExists(t, filepath.Join(repoRoot, ".devcontainer", "devcontainer.user.json"))
}

func TestRenderDevcontainerJSONAppendsUserArrays(t *testing.T) {
	repoRoot := t.TempDir()
	if err := os.MkdirAll(filepath.Join(repoRoot, ".devcontainer"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(repoRoot, ".devcontainer", "devcontainer.user.json"), []byte(`{
		"customizations": {
			"vscode": {
				"extensions": ["ms-python.python"]
			}
		}
	}`), 0o644); err != nil {
		t.Fatalf("write user json: %v", err)
	}

	outputFile := filepath.Join(repoRoot, ".devcontainer", "devcontainer.json")
	if err := renderDevcontainerJSON(repoRoot, "claude", outputFile); err != nil {
		t.Fatalf("renderDevcontainerJSON failed: %v", err)
	}

	data := readJSONMap(t, outputFile)
	extensions := data["customizations"].(map[string]any)["vscode"].(map[string]any)["extensions"].([]any)
	if len(extensions) != 2 || extensions[0].(string) != "anthropic.claude-code" || extensions[1].(string) != "ms-python.python" {
		t.Fatalf("unexpected extensions: %v", extensions)
	}
}

func readCompose(t *testing.T, path string) composeDocument {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	var doc composeDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("unmarshal %s: %v", path, err)
	}
	return doc
}

func readPolicy(t *testing.T, path string) policyDocument {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	var doc policyDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("unmarshal %s: %v", path, err)
	}
	return doc
}

func readJSONMap(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal %s: %v", path, err)
	}
	return decoded
}

func assertContains(t *testing.T, values []string, want string) {
	t.Helper()
	for _, value := range values {
		if value == want {
			return
		}
	}
	t.Fatalf("expected %q in %v", want, values)
}

func assertNotContains(t *testing.T, values []string, want string) {
	t.Helper()
	for _, value := range values {
		if value == want {
			t.Fatalf("did not expect %q in %v", want, values)
		}
	}
}

func assertFileExists(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("expected %s to exist: %v", path, err)
	}
}

func mapLookup(values map[string]string) func(string) string {
	return func(key string) string {
		return values[key]
	}
}
