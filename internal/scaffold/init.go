package scaffold

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
)

type InitParams struct {
	RepoRoot    string
	Agent       string
	ProjectName string
	IDE         string
	Runner      docker.Runner
	Stderr      io.Writer
	LookupEnv   func(string) string
}

type EnvConfig struct {
	ProxyImage                string
	AgentImage                string
	MountClaudeConfig         bool
	EnableShellCustomizations bool
	EnableDotfiles            bool
	MountGitReadonly          bool
	MountIdeaReadonly         bool
	MountVSCodeReadonly       bool
}

func InitializeCLI(ctx context.Context, params InitParams) error {
	if err := runtime.ValidateAgent(params.Agent); err != nil {
		return err
	}
	if params.RepoRoot == "" {
		return fmt.Errorf("repo root is required")
	}
	if params.ProjectName == "" {
		return fmt.Errorf("project name is required")
	}

	env := loadEnvConfig(params, runtime.ModeCLI)
	if err := writeCLIBaseComposeFile(ctx, params, env); err != nil {
		return err
	}
	if err := writeUserOverrideIfMissing(params.RepoRoot, runtime.CLIUserOverrideFile(params.RepoRoot), "compose/user.override.yml", optionalSharedVolumes(env)); err != nil {
		return err
	}
	if err := scaffoldUserPolicyFileIfMissing(runtime.SharedPolicyFile(params.RepoRoot), "user.policy.yaml"); err != nil {
		return err
	}
	if err := scaffoldUserPolicyFileIfMissing(runtime.UserAgentPolicyFile(params.RepoRoot, params.Agent), "user.agent.policy.yaml"); err != nil {
		return err
	}
	if err := writeCLIAgentComposeFile(ctx, params, env); err != nil {
		return err
	}
	if err := writeUserOverrideIfMissing(params.RepoRoot, runtime.CLIUserAgentOverrideFile(params.RepoRoot, params.Agent), "compose/user.agent.override.yml", optionalAgentVolumes(params.Agent, env)); err != nil {
		return err
	}

	return nil
}

func InitializeDevcontainer(ctx context.Context, params InitParams) error {
	if err := runtime.ValidateDevcontainerIDE(params.IDE); err != nil {
		return err
	}

	if err := InitializeCLI(ctx, InitParams{
		RepoRoot:    params.RepoRoot,
		Agent:       params.Agent,
		ProjectName: params.ProjectName,
		Runner:      params.Runner,
		Stderr:      params.Stderr,
		LookupEnv:   wrapLookupIgnoringIDE(params.LookupEnv),
	}); err != nil {
		return err
	}
	if err := scaffoldDevcontainerUserJSONIfMissing(params.RepoRoot); err != nil {
		return err
	}
	if err := renderDevcontainerJSON(params.RepoRoot, params.Agent, runtime.DevcontainerJSONFile(params.RepoRoot)); err != nil {
		return err
	}
	if err := writeDevcontainerModeComposeFile(params.RepoRoot, params.IDE, params.ProjectName); err != nil {
		return err
	}
	if err := writeDevcontainerPolicyFile(runtime.DevcontainerManagedPolicyFile(params.RepoRoot), params.IDE); err != nil {
		return err
	}
	cleanupLegacyDevcontainerManagedFiles(params.RepoRoot)

	return nil
}

func loadEnvConfig(params InitParams, mode string) EnvConfig {
	lookup := params.LookupEnv
	if lookup == nil {
		lookup = os.Getenv
	}

	config := EnvConfig{
		ProxyImage:                envOrDefault(lookup("AGENTBOX_PROXY_IMAGE"), "ghcr.io/mattolson/agent-sandbox-proxy:latest"),
		AgentImage:                envOrDefault(lookup("AGENTBOX_AGENT_IMAGE"), fmt.Sprintf("ghcr.io/mattolson/agent-sandbox-%s:latest", params.Agent)),
		MountClaudeConfig:         parseBoolEnv(lookup("AGENTBOX_MOUNT_CLAUDE_CONFIG")),
		EnableShellCustomizations: parseBoolEnv(lookup("AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS")),
		EnableDotfiles:            parseBoolEnv(lookup("AGENTBOX_ENABLE_DOTFILES")),
		MountGitReadonly:          parseBoolEnv(lookup("AGENTBOX_MOUNT_GIT_READONLY")),
		MountIdeaReadonly:         parseBoolEnv(lookup("AGENTBOX_MOUNT_IDEA_READONLY")),
		MountVSCodeReadonly:       parseBoolEnv(lookup("AGENTBOX_MOUNT_VSCODE_READONLY")),
	}

	if mode == runtime.ModeDevcontainer {
		config.MountIdeaReadonly = false
		config.MountVSCodeReadonly = false
	}

	return config
}

func parseBoolEnv(value string) bool {
	return strings.EqualFold(value, "true")
}

func envOrDefault(value string, fallback string) string {
	if value == "" {
		return fallback
	}

	return value
}

func optionalSharedVolumes(config EnvConfig) []string {
	volumes := make([]string, 0, 5)
	if config.EnableShellCustomizations {
		volumes = append(volumes, `${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro`)
	}
	if config.EnableDotfiles {
		volumes = append(volumes, `${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro`)
	}
	if config.MountGitReadonly {
		volumes = append(volumes, `../../.git:/workspace/.git:ro`)
	}
	if config.MountIdeaReadonly {
		volumes = append(volumes, `../../.idea:/workspace/.idea:ro`)
	}
	if config.MountVSCodeReadonly {
		volumes = append(volumes, `../../.vscode:/workspace/.vscode:ro`)
	}

	return volumes
}

func optionalAgentVolumes(agent string, config EnvConfig) []string {
	if agent != "claude" || !config.MountClaudeConfig {
		return nil
	}

	return []string{
		`${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro`,
		`${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro`,
	}
}

func writeTemplateIfMissing(path string, templateName string) error {
	if _, err := os.Stat(path); err == nil {
		return nil
	}

	data, err := ReadTemplate(templateName)
	if err != nil {
		return err
	}
	return writeFileIfChanged(path, data, 0o644)
}

func writeFileIfChanged(path string, data []byte, mode os.FileMode) error {
	if existing, err := os.ReadFile(path); err == nil && bytes.Equal(existing, data) {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmpFile := path + ".tmp"
	if err := os.WriteFile(tmpFile, data, mode); err != nil {
		return err
	}
	return os.Rename(tmpFile, path)
}

func wrapLookupIgnoringIDE(lookup func(string) string) func(string) string {
	if lookup == nil {
		lookup = os.Getenv
	}

	return func(name string) string {
		switch name {
		case "AGENTBOX_MOUNT_IDEA_READONLY", "AGENTBOX_MOUNT_VSCODE_READONLY":
			return ""
		default:
			return lookup(name)
		}
	}
}
