package scaffold

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
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
	assertContainsManagedBind(t, base.Services.Proxy.Volumes, sharedPolicyMountSource, sharedPolicyMountTarget, true)
	assertProxySecretRuntime(t, base.Services.Proxy)
	assertNoProxySecretRuntime(t, base.Services.Agent)
	assertCredentialShimRuntime(t, base)
	if base.Services.Proxy.Image != "agent-sandbox-proxy:local" {
		t.Fatalf("unexpected proxy image: %q", base.Services.Proxy.Image)
	}

	agent := readCompose(t, runtime.CLIAgentComposeFile(repoRoot, "claude"))
	if agent.Services.Agent.Image != "agent-sandbox-claude:local" {
		t.Fatalf("unexpected agent image: %q", agent.Services.Agent.Image)
	}
	assertContainsManagedBind(t, agent.Services.Proxy.Volumes, "../policy/user.agent.claude.policy.yaml", "/etc/agent-sandbox/policy/user.agent.policy.yaml", true)
	assertContains(t, agent.Services.Proxy.Environment, "AGENTBOX_ACTIVE_AGENT=claude")
	assertNoProxySecretRuntime(t, agent.Services.Agent)
	assertContainsVolumeString(t, agent.Services.Agent.Volumes, "claude-state:/home/dev/.claude")
	assertContainsVolumeString(t, agent.Services.Agent.Volumes, "claude-history:/commandhistory")

	sharedOverride := readCompose(t, runtime.CLIUserOverrideFile(repoRoot))
	for _, volume := range []string{
		`${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro`,
		`${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro`,
		`../../.git:/workspace/.git:ro`,
		`../../.idea:/workspace/.idea:ro`,
		`../../.vscode:/workspace/.vscode:ro`,
	} {
		assertContainsVolumeString(t, sharedOverride.Services.Agent.Volumes, volume)
	}
	assertNoProxySecretRuntime(t, sharedOverride.Services.Agent)

	agentOverride := readCompose(t, runtime.CLIUserAgentOverrideFile(repoRoot, "claude"))
	assertContainsVolumeString(t, agentOverride.Services.Agent.Volumes, `${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro`)
	assertContainsVolumeString(t, agentOverride.Services.Agent.Volumes, `${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro`)
	assertNoProxySecretRuntime(t, agentOverride.Services.Agent)

	assertCredentialShimAgentReadOnly(t, base, agent, sharedOverride, agentOverride)

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

	base := readCompose(t, runtime.CLIBaseComposeFile(repoRoot))
	assertProxySecretRuntime(t, base.Services.Proxy)
	assertNoProxySecretRuntime(t, base.Services.Agent)
	assertCredentialShimRuntime(t, base)

	modeFile := readCompose(t, runtime.CLIDevcontainerModeComposeFile(repoRoot))
	if modeFile.Name != "project-sandbox-devcontainer" {
		t.Fatalf("unexpected mode project name: %q", modeFile.Name)
	}
	assertContainsManagedBind(t, modeFile.Services.Proxy.Volumes, "../policy/policy.devcontainer.yaml", "/etc/agent-sandbox/policy/devcontainer.policy.yaml", true)
	assertContainsManagedBind(t, modeFile.Services.Agent.Volumes, "../../.devcontainer", "/workspace/.devcontainer", true)
	assertContainsManagedBind(t, modeFile.Services.Agent.Volumes, "../../.vscode", "/workspace/.vscode", true)
	assertNoVolumeTarget(t, modeFile.Services.Agent.Volumes, "/workspace/.idea")
	assertNoProxySecretRuntime(t, modeFile.Services.Agent)

	sharedOverride := readCompose(t, runtime.CLIUserOverrideFile(repoRoot))
	assertNotContainsVolumeString(t, sharedOverride.Services.Agent.Volumes, "../../.idea:/workspace/.idea:ro")
	assertNotContainsVolumeString(t, sharedOverride.Services.Agent.Volumes, "../../.vscode:/workspace/.vscode:ro")
	assertContainsVolumeString(t, sharedOverride.Services.Agent.Volumes, `${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro`)
	assertNoProxySecretRuntime(t, sharedOverride.Services.Agent)
	assertCredentialShimAgentReadOnly(t, base, modeFile, sharedOverride)

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

func assertContainsVolumeString(t *testing.T, values composeVolumes, want string) {
	t.Helper()
	for _, value := range values {
		if existing, ok := value.stringValue(); ok && existing == want {
			return
		}
	}
	t.Fatalf("expected volume string %q in %v", want, values)
}

func assertNotContainsVolumeString(t *testing.T, values composeVolumes, want string) {
	t.Helper()
	for _, value := range values {
		if existing, ok := value.stringValue(); ok && existing == want {
			t.Fatalf("did not expect volume string %q in %v", want, values)
		}
	}
}

func assertContainsManagedBind(t *testing.T, values composeVolumes, source string, target string, readOnly bool) {
	t.Helper()
	for _, value := range values {
		mount, ok := value.bindMount()
		if !ok || mount.Source != source || mount.Target != target {
			continue
		}
		if mount.ReadOnly != readOnly {
			t.Fatalf("volume %s -> %s read_only=%v, want %v", source, target, mount.ReadOnly, readOnly)
		}
		if !mount.HasCreateHostPath || mount.CreateHostPath {
			t.Fatalf("volume %s -> %s must set bind.create_host_path: false", source, target)
		}
		return
	}
	t.Fatalf("expected managed bind %s -> %s in %v", source, target, values)
}

func assertNoVolumeTarget(t *testing.T, values composeVolumes, target string) {
	t.Helper()
	for _, value := range values {
		mount, ok := value.bindMount()
		if ok && mount.Target == target {
			t.Fatalf("did not expect volume target %q in %v", target, values)
		}
	}
}

func assertProxySecretRuntime(t *testing.T, service *composeService) {
	t.Helper()
	if service == nil {
		t.Fatal("expected service to exist")
	}
	assertContainsManagedBind(t, service.Volumes, proxySecretMountSource, proxySecretMountTarget, true)
}

func assertCredentialShimRuntime(t *testing.T, doc composeDocument) {
	t.Helper()
	hasNamedVolume := false
	for _, volume := range doc.Volumes {
		if volume.Name == credentialShimVolumeName {
			hasNamedVolume = true
			break
		}
	}
	if !hasNamedVolume {
		t.Fatalf("expected top-level named volume %q in %+v", credentialShimVolumeName, doc.Volumes)
	}
	if doc.Services.Proxy == nil {
		t.Fatal("expected proxy service to exist")
	}
	if doc.Services.Agent == nil {
		t.Fatal("expected agent service to exist")
	}
	assertContainsVolumeString(t, doc.Services.Proxy.Volumes, credentialShimVolume)
	assertContainsVolumeString(t, doc.Services.Agent.Volumes, credentialShimReadonlyVolume)
	assertNoVolumeReference(t, doc.Services.Agent.Volumes, proxySecretMountTarget)
}

func assertNoProxySecretRuntime(t *testing.T, service *composeService) {
	t.Helper()
	if service == nil {
		return
	}
	for _, entry := range service.Environment {
		if strings.HasPrefix(entry, "AGENTBOX_SECRET_SOURCE=") {
			t.Fatalf("did not expect proxy secret env in %v", service.Environment)
		}
	}
	for _, value := range []string{
		proxySecretMountTarget,
		"AGENTBOX_SECRET_DIR",
		".config/agent-sandbox/secrets",
	} {
		assertNoVolumeReference(t, service.Volumes, value)
	}
}

// assertCredentialShimAgentReadOnly walks the provided compose documents and
// fails the test if any agent service entry mounts the credential-shim target
// without the read-only flag. This guards against a managed override layer
// quietly upgrading agent access to read/write.
func assertCredentialShimAgentReadOnly(t *testing.T, docs ...composeDocument) {
	t.Helper()
	for _, doc := range docs {
		if doc.Services.Agent == nil {
			continue
		}
		for _, volume := range doc.Services.Agent.Volumes {
			mount, ok := volume.bindMount()
			if !ok {
				continue
			}
			if mount.Target != credentialShimMountTarget {
				continue
			}
			if !mount.ReadOnly {
				t.Fatalf(
					"agent mount of %q must be read-only, got source=%q read_only=%v",
					credentialShimMountTarget, mount.Source, mount.ReadOnly,
				)
			}
		}
	}
}

func assertNoVolumeReference(t *testing.T, values composeVolumes, want string) {
	t.Helper()
	for _, value := range values {
		if yamlNodeContains(value.node, want) {
			t.Fatalf("did not expect volume reference %q in %v", want, values)
		}
	}
}

func yamlNodeContains(node *yaml.Node, want string) bool {
	if node == nil {
		return false
	}
	if strings.Contains(node.Value, want) {
		return true
	}
	for _, child := range node.Content {
		if yamlNodeContains(child, want) {
			return true
		}
	}
	return false
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
