package runtime

import (
	"fmt"
	"path/filepath"
	"strings"
)

func LegacyUpgradeGuidePath() string {
	return "docs/upgrades/m8-layered-layout.md"
}

func LegacyCLIComposeFile(repoRoot string) string {
	return filepath.Join(AgentSandboxDir(repoRoot), "docker-compose.yml")
}

func LegacyDevcontainerComposeFile(repoRoot string) string {
	return filepath.Join(repoRoot, ".devcontainer", "docker-compose.yml")
}

func LegacyDevcontainerPolicyFile(repoRoot string, agent string) string {
	return filepath.Join(AgentSandboxDir(repoRoot), fmt.Sprintf("policy-devcontainer-%s.yaml", agent))
}

func LegacyCLIPolicyFile(repoRoot string, agent string) string {
	return filepath.Join(AgentSandboxDir(repoRoot), fmt.Sprintf("policy-cli-%s.yaml", agent))
}

func UnsupportedLegacyLayoutFiles(repoRoot string) []string {
	files := make([]string, 0)

	for _, candidate := range []string{
		LegacyCLIComposeFile(repoRoot),
		LegacyDevcontainerComposeFile(repoRoot),
	} {
		if fileExists(candidate) {
			files = append(files, candidate)
		}
	}

	for _, agent := range SupportedAgents() {
		for _, candidate := range []string{
			LegacyDevcontainerPolicyFile(repoRoot, agent),
			LegacyCLIPolicyFile(repoRoot, agent),
		} {
			if fileExists(candidate) {
				files = append(files, candidate)
			}
		}
	}

	return files
}

func AbortIfUnsupportedLegacyLayout(repoRoot string, commandName string, preferredAgent string, preferredMode string, preferredIDE string) error {
	files := UnsupportedLegacyLayoutFiles(repoRoot)
	if len(files) == 0 {
		return nil
	}

	return fmt.Errorf("%s", RenderLegacyLayoutError(repoRoot, commandName, preferredAgent, preferredMode, preferredIDE, files))
}

func RenderLegacyLayoutError(repoRoot string, commandName string, preferredAgent string, preferredMode string, preferredIDE string, files []string) string {
	resolvedAgent := inferLegacyLayoutAgent(repoRoot, files, preferredAgent)
	resolvedMode := inferLegacyLayoutMode(repoRoot, files, preferredMode)
	agentLabel := "<agent>"
	if resolvedAgent != "" {
		agentLabel = resolvedAgent
	}

	initCommand := "agentbox init"
	if resolvedAgent != "" {
		initCommand += " --agent " + resolvedAgent
	} else {
		initCommand += " --agent <agent>"
	}

	switch resolvedMode {
	case ModeCLI:
		initCommand += " --mode cli"
	case ModeDevcontainer:
		initCommand += " --mode devcontainer"
		if preferredIDE != "" {
			initCommand += " --ide " + preferredIDE
		} else {
			initCommand += " --ide <vscode|jetbrains|none>"
		}
	default:
		initCommand += " --mode <cli|devcontainer>"
	}

	var builder strings.Builder
	fmt.Fprintf(&builder, "agentbox %s does not support the legacy single-file layout.\n\n", commandName)
	builder.WriteString("Found legacy generated files:\n")
	for _, file := range files {
		fmt.Fprintf(&builder, "- %s\n", legacyLayoutRelativePath(repoRoot, file))
	}

	builder.WriteString("\nTo upgrade safely:\n")
	builder.WriteString("1. Rename the legacy generated files so agentbox no longer treats them as live config:\n")
	for _, file := range files {
		fmt.Fprintf(&builder, "   %s -> %s\n", legacyLayoutRelativePath(repoRoot, file), legacyLayoutRelativePath(repoRoot, legacyLayoutRenamePath(file)))
	}
	builder.WriteString("2. Re-run:\n")
	fmt.Fprintf(&builder, "   %s\n", initCommand)
	builder.WriteString("3. Copy your customizations into the new user-owned files:\n")
	builder.WriteString("   .agent-sandbox/compose/user.override.yml\n")
	fmt.Fprintf(&builder, "   .agent-sandbox/compose/user.agent.%s.override.yml\n", agentLabel)
	builder.WriteString("   .agent-sandbox/policy/user.policy.yaml\n")
	fmt.Fprintf(&builder, "   .agent-sandbox/policy/user.agent.%s.policy.yaml\n", agentLabel)
	if resolvedMode == ModeDevcontainer || fileExists(LegacyDevcontainerComposeFile(repoRoot)) {
		builder.WriteString("   .devcontainer/devcontainer.user.json\n")
	}
	builder.WriteString("\nDo not copy customizations back into managed files under .agent-sandbox/compose/.\n")
	fmt.Fprintf(&builder, "See %s for the full upgrade guide.", LegacyUpgradeGuidePath())

	return builder.String()
}

func inferLegacyLayoutMode(repoRoot string, files []string, preferredMode string) string {
	if preferredMode != "" {
		return preferredMode
	}

	resolvedMode := ""
	for _, file := range files {
		fileMode := legacyLayoutFileMode(repoRoot, file)
		if fileMode == "" {
			continue
		}
		if resolvedMode == "" {
			resolvedMode = fileMode
			continue
		}
		if resolvedMode != fileMode {
			return ""
		}
	}

	return resolvedMode
}

func inferLegacyLayoutAgent(repoRoot string, files []string, preferredAgent string) string {
	if preferredAgent != "" {
		return preferredAgent
	}

	resolvedAgent := ""
	for _, file := range files {
		agent := legacyLayoutFileAgent(file)
		if agent == "" {
			continue
		}
		if resolvedAgent == "" {
			resolvedAgent = agent
			continue
		}
		if resolvedAgent != agent {
			return ""
		}
	}

	return resolvedAgent
}

func legacyLayoutFileMode(repoRoot string, file string) string {
	relative := legacyLayoutRelativePath(repoRoot, file)
	switch relative {
	case filepath.ToSlash(filepath.Join(AgentSandboxDirName, "docker-compose.yml")):
		return ModeCLI
	}

	if strings.HasPrefix(relative, filepath.ToSlash(filepath.Join(AgentSandboxDirName, "policy-cli-"))) && strings.HasSuffix(relative, ".yaml") {
		return ModeCLI
	}
	if relative == filepath.ToSlash(filepath.Join(".devcontainer", "docker-compose.yml")) {
		return ModeDevcontainer
	}
	if strings.HasPrefix(relative, filepath.ToSlash(filepath.Join(AgentSandboxDirName, "policy-devcontainer-"))) && strings.HasSuffix(relative, ".yaml") {
		return ModeDevcontainer
	}

	return ""
}

func legacyLayoutFileAgent(file string) string {
	base := filepath.Base(file)
	switch {
	case strings.HasPrefix(base, "policy-cli-") && strings.HasSuffix(base, ".yaml"):
		return strings.TrimSuffix(strings.TrimPrefix(base, "policy-cli-"), ".yaml")
	case strings.HasPrefix(base, "policy-devcontainer-") && strings.HasSuffix(base, ".yaml"):
		return strings.TrimSuffix(strings.TrimPrefix(base, "policy-devcontainer-"), ".yaml")
	default:
		return ""
	}
}

func legacyLayoutRenamePath(file string) string {
	directory := filepath.Dir(file)
	base := filepath.Base(file)
	stem := base
	extension := ""

	switch {
	case strings.HasSuffix(base, ".yaml"):
		stem = strings.TrimSuffix(base, ".yaml")
		extension = ".yaml"
	case strings.HasSuffix(base, ".yml"):
		stem = strings.TrimSuffix(base, ".yml")
		extension = ".yml"
	case strings.HasSuffix(base, ".json"):
		stem = strings.TrimSuffix(base, ".json")
		extension = ".json"
	}

	return filepath.Join(directory, stem+".legacy"+extension)
}

func legacyLayoutRelativePath(repoRoot string, file string) string {
	relative, err := filepath.Rel(repoRoot, file)
	if err != nil || strings.HasPrefix(relative, "..") {
		return filepath.ToSlash(file)
	}

	return filepath.ToSlash(relative)
}
