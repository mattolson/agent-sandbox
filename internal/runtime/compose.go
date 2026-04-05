package runtime

import (
	"fmt"
	"os"
	"path/filepath"
)

// Layout identifies the managed compose topology present for a repo.
type Layout string

const (
	LayoutLayeredCLI Layout = "layered-cli"
	// LayoutCentralizedDevcontainer distinguishes the current .agent-sandbox-backed
	// devcontainer runtime from the older .devcontainer sidecar layout.
	LayoutCentralizedDevcontainer Layout = "centralized-devcontainer"
)

// ComposeStack describes the resolved compose files and active target for a runtime invocation.
type ComposeStack struct {
	RepoRoot string
	Layout   Layout
	Target   ActiveTarget
	Files    []string
}

func ComposeDir(repoRoot string) string {
	return filepath.Join(AgentSandboxDir(repoRoot), "compose")
}

func CLIBaseComposeFile(repoRoot string) string {
	return filepath.Join(ComposeDir(repoRoot), "base.yml")
}

func CLIAgentComposeFile(repoRoot string, agent string) string {
	return filepath.Join(ComposeDir(repoRoot), fmt.Sprintf("agent.%s.yml", agent))
}

func CLIDevcontainerModeComposeFile(repoRoot string) string {
	return filepath.Join(ComposeDir(repoRoot), "mode.devcontainer.yml")
}

func CLIUserOverrideFile(repoRoot string) string {
	return filepath.Join(ComposeDir(repoRoot), "user.override.yml")
}

func CLIUserAgentOverrideFile(repoRoot string, agent string) string {
	return filepath.Join(ComposeDir(repoRoot), fmt.Sprintf("user.agent.%s.override.yml", agent))
}

func DevcontainerJSONFile(repoRoot string) string {
	return filepath.Join(repoRoot, ".devcontainer", "devcontainer.json")
}

func DetectLayout(repoRoot string) (Layout, bool) {
	if fileExists(CLIDevcontainerModeComposeFile(repoRoot)) {
		return LayoutCentralizedDevcontainer, true
	}
	if fileExists(CLIBaseComposeFile(repoRoot)) {
		return LayoutLayeredCLI, true
	}

	return "", false
}

func ResolveComposeStack(repoRoot string) (ComposeStack, error) {
	layout, ok := DetectLayout(repoRoot)
	if !ok {
		return ComposeStack{}, fmt.Errorf("No layered compose layout found at %s. Run 'agentbox init' first.", repoRoot)
	}

	target, err := ReadActiveTarget(repoRoot)
	if err != nil {
		switch layout {
		case LayoutCentralizedDevcontainer:
			return ComposeStack{}, fmt.Errorf("Active agent state missing for centralized devcontainer layout at %s. Run 'agentbox switch --agent <name>'.", repoRoot)
		case LayoutLayeredCLI:
			return ComposeStack{}, fmt.Errorf("Active agent state missing for layered CLI compose at %s. Run 'agentbox switch --agent <name>'.", repoRoot)
		default:
			return ComposeStack{}, err
		}
	}

	var files []string
	switch layout {
	case LayoutCentralizedDevcontainer:
		files, err = EmitDevcontainerComposeFiles(repoRoot, target.ActiveAgent)
		if err != nil {
			return ComposeStack{}, fmt.Errorf("Failed to resolve devcontainer compose files for %s.", repoRoot)
		}
	case LayoutLayeredCLI:
		files, err = EmitCLIComposeFiles(repoRoot, target.ActiveAgent)
		if err != nil {
			return ComposeStack{}, fmt.Errorf("Failed to resolve layered CLI compose files for %s.", repoRoot)
		}
	default:
		return ComposeStack{}, fmt.Errorf("unsupported layout: %s", layout)
	}

	return ComposeStack{
		RepoRoot: repoRoot,
		Layout:   layout,
		Target:   target,
		Files:    files,
	}, nil
}

func EmitCLIComposeFiles(repoRoot string, agent string) ([]string, error) {
	if agent == "" {
		target, err := ReadActiveTarget(repoRoot)
		if err != nil {
			return nil, fmt.Errorf("Active agent state missing for layered CLI compose at %s. Run 'agentbox switch --agent <name>'.", repoRoot)
		}
		agent = target.ActiveAgent
	}
	if err := ValidateAgent(agent); err != nil {
		return nil, err
	}

	baseFile := CLIBaseComposeFile(repoRoot)
	agentFile := CLIAgentComposeFile(repoRoot, agent)
	sharedOverride := CLIUserOverrideFile(repoRoot)
	agentOverride := CLIUserAgentOverrideFile(repoRoot, agent)

	if !fileExists(baseFile) {
		return nil, fmt.Errorf("Layered CLI compose base file not found: %s", baseFile)
	}
	if !fileExists(agentFile) {
		return nil, fmt.Errorf("Layered CLI compose agent file not found for '%s': %s", agent, agentFile)
	}

	files := []string{baseFile, agentFile}
	if fileExists(sharedOverride) {
		files = append(files, sharedOverride)
	}
	if fileExists(agentOverride) {
		files = append(files, agentOverride)
	}

	return files, nil
}

func EmitDevcontainerComposeFiles(repoRoot string, agent string) ([]string, error) {
	if agent == "" {
		target, err := ReadActiveTarget(repoRoot)
		if err != nil {
			return nil, fmt.Errorf("Active agent state missing for centralized devcontainer layout at %s. Run 'agentbox switch --agent <name>'.", repoRoot)
		}
		agent = target.ActiveAgent
	}
	if err := ValidateAgent(agent); err != nil {
		return nil, err
	}

	baseFile := CLIBaseComposeFile(repoRoot)
	agentFile := CLIAgentComposeFile(repoRoot, agent)
	modeFile := CLIDevcontainerModeComposeFile(repoRoot)
	sharedOverride := CLIUserOverrideFile(repoRoot)
	agentOverride := CLIUserAgentOverrideFile(repoRoot, agent)

	if !fileExists(baseFile) {
		return nil, fmt.Errorf("Devcontainer compose base file not found: %s", baseFile)
	}
	if !fileExists(agentFile) {
		return nil, fmt.Errorf("Devcontainer compose agent file not found for '%s': %s", agent, agentFile)
	}
	if !fileExists(modeFile) {
		return nil, fmt.Errorf("Devcontainer compose mode overlay not found: %s", modeFile)
	}

	files := []string{baseFile, agentFile, modeFile}
	if fileExists(sharedOverride) {
		files = append(files, sharedOverride)
	}
	if fileExists(agentOverride) {
		files = append(files, agentOverride)
	}

	return files, nil
}

func ComposeCommandRequiresRuntimeSync(command string, skipRuntimeSync bool) bool {
	if skipRuntimeSync {
		return false
	}

	switch command {
	case "up", "run", "create", "restart", "start":
		return true
	default:
		return false
	}
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
