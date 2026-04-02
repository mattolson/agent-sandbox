package scaffold

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"gopkg.in/yaml.v3"
)

type composeDocument struct {
	Name     string          `yaml:"name,omitempty"`
	Services composeServices `yaml:"services,omitempty"`
	Volumes  map[string]any  `yaml:"volumes,omitempty"`
}

type composeServices struct {
	Proxy *composeService `yaml:"proxy,omitempty"`
	Agent *composeService `yaml:"agent,omitempty"`
}

type composeService struct {
	Image       string                      `yaml:"image,omitempty"`
	DependsOn   map[string]composeCondition `yaml:"depends_on,omitempty"`
	CapDrop     []string                    `yaml:"cap_drop,omitempty"`
	CapAdd      []string                    `yaml:"cap_add,omitempty"`
	Volumes     []string                    `yaml:"volumes,omitempty"`
	WorkingDir  string                      `yaml:"working_dir,omitempty"`
	StdinOpen   bool                        `yaml:"stdin_open,omitempty"`
	TTY         bool                        `yaml:"tty,omitempty"`
	Environment []string                    `yaml:"environment,omitempty"`
	Healthcheck *composeHealthcheck         `yaml:"healthcheck,omitempty"`
}

type composeCondition struct {
	Condition string `yaml:"condition,omitempty"`
}

type composeHealthcheck struct {
	Test     []string `yaml:"test,omitempty"`
	Interval string   `yaml:"interval,omitempty"`
	Timeout  string   `yaml:"timeout,omitempty"`
	Retries  int      `yaml:"retries,omitempty"`
}

func writeCLIBaseComposeFile(ctx context.Context, params InitParams, env EnvConfig) error {
	doc, header, err := loadComposeTemplate("compose/base.yml")
	if err != nil {
		return err
	}
	ensureProxyService(&doc)
	pinnedProxyImage, err := docker.ResolvePinnedImage(ctx, params.Runner, env.ProxyImage, params.Stderr)
	if err != nil {
		return err
	}

	doc.Name = runtime.ApplyModeSuffix(params.ProjectName, runtime.ModeCLI)
	doc.Services.Proxy.Image = pinnedProxyImage
	doc.Services.Proxy.Volumes = ensureString(doc.Services.Proxy.Volumes, "../policy/user.policy.yaml:/etc/agent-sandbox/policy/user.policy.yaml:ro")

	return writeComposeDocument(runtime.CLIBaseComposeFile(params.RepoRoot), header, doc)
}

func writeCLIAgentComposeFile(ctx context.Context, params InitParams, env EnvConfig) error {
	doc, header, err := loadComposeTemplate(fmt.Sprintf("%s/cli/agent.yml", params.Agent))
	if err != nil {
		return err
	}
	ensureProxyService(&doc)
	ensureAgentService(&doc)
	pinnedAgentImage, err := docker.ResolvePinnedImage(ctx, params.Runner, env.AgentImage, params.Stderr)
	if err != nil {
		return err
	}

	doc.Services.Agent.Image = pinnedAgentImage
	legacyPolicyVolume := fmt.Sprintf("../policy-cli-%s.yaml:/etc/mitmproxy/policy.yaml:ro", params.Agent)
	doc.Services.Proxy.Volumes = removeString(doc.Services.Proxy.Volumes, legacyPolicyVolume)
	doc.Services.Proxy.Volumes = ensureString(doc.Services.Proxy.Volumes, fmt.Sprintf("../policy/user.agent.%s.policy.yaml:/etc/agent-sandbox/policy/user.agent.policy.yaml:ro", params.Agent))
	doc.Services.Proxy.Environment = setEnvironmentVar(doc.Services.Proxy.Environment, "AGENTBOX_ACTIVE_AGENT", params.Agent)

	return writeComposeDocument(runtime.CLIAgentComposeFile(params.RepoRoot, params.Agent), header, doc)
}

func writeUserOverrideIfMissing(repoRoot string, outputFile string, templateName string, extraVolumes []string) error {
	if _, err := os.Stat(outputFile); err == nil {
		return nil
	}

	doc, header, err := loadComposeTemplate(templateName)
	if err != nil {
		return err
	}
	ensureAgentService(&doc)
	for _, volume := range extraVolumes {
		doc.Services.Agent.Volumes = ensureString(doc.Services.Agent.Volumes, volume)
	}

	return writeComposeDocument(outputFile, header, doc)
}

func writeDevcontainerModeComposeFile(repoRoot string, ide string, projectName string) error {
	doc, header, err := loadComposeTemplate("compose/mode.devcontainer.yml")
	if err != nil {
		return err
	}
	ensureAgentService(&doc)
	doc.Name = runtime.ApplyModeSuffix(projectName, runtime.ModeDevcontainer)
	if ide == "jetbrains" {
		doc.Services.Agent.Volumes = ensureString(doc.Services.Agent.Volumes, "../../.idea:/workspace/.idea:ro")
		for _, capability := range []string{"DAC_OVERRIDE", "CHOWN", "FOWNER"} {
			doc.Services.Agent.CapAdd = ensureString(doc.Services.Agent.CapAdd, capability)
		}
	} else if ide == "vscode" {
		doc.Services.Agent.Volumes = ensureString(doc.Services.Agent.Volumes, "../../.vscode:/workspace/.vscode:ro")
	}

	return writeComposeDocument(runtime.CLIDevcontainerModeComposeFile(repoRoot), header, doc)
}

func loadComposeTemplate(templateName string) (composeDocument, string, error) {
	data, err := ReadTemplate(templateName)
	if err != nil {
		return composeDocument{}, "", err
	}

	var doc composeDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return composeDocument{}, "", err
	}

	return doc, leadingCommentBlock(string(data)), nil
}

func writeComposeDocument(path string, header string, doc composeDocument) error {
	body, err := yaml.Marshal(doc)
	if err != nil {
		return err
	}

	return writeFileIfChanged(path, prependHeader(header, body), 0o644)
}

func ensureProxyService(doc *composeDocument) {
	if doc.Services.Proxy == nil {
		doc.Services.Proxy = &composeService{}
	}
}

func ensureAgentService(doc *composeDocument) {
	if doc.Services.Agent == nil {
		doc.Services.Agent = &composeService{}
	}
}

func ensureString(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}

	return append(values, value)
}

func removeString(values []string, target string) []string {
	filtered := make([]string, 0, len(values))
	for _, value := range values {
		if value != target {
			filtered = append(filtered, value)
		}
	}

	return filtered
}

func setEnvironmentVar(values []string, name string, value string) []string {
	prefix := name + "="
	filtered := make([]string, 0, len(values)+1)
	for _, entry := range values {
		if !strings.HasPrefix(entry, prefix) {
			filtered = append(filtered, entry)
		}
	}

	return append(filtered, prefix+value)
}
