package runtime

import "os"

func AgentSandboxInitialized(repoRoot string) bool {
	info, err := os.Stat(AgentSandboxDir(repoRoot))
	return err == nil && info.IsDir()
}

func CLILayeredComposeInitialized(repoRoot string) bool {
	return fileExists(CLIBaseComposeFile(repoRoot))
}

func DevcontainerCentralizedRuntimeInitialized(repoRoot string) bool {
	return fileExists(CLIDevcontainerModeComposeFile(repoRoot))
}

func PreferredManagedLayout(repoRoot string) (Layout, bool) {
	if DevcontainerCentralizedRuntimeInitialized(repoRoot) {
		return LayoutCentralizedDevcontainer, true
	}
	if CLILayeredComposeInitialized(repoRoot) {
		return LayoutLayeredCLI, true
	}

	return "", false
}

func ResolveComposeFilesForLayout(repoRoot string, layout Layout, agent string) ([]string, error) {
	switch layout {
	case LayoutCentralizedDevcontainer:
		return EmitDevcontainerComposeFiles(repoRoot, agent)
	case LayoutLayeredCLI:
		return EmitCLIComposeFiles(repoRoot, agent)
	default:
		return nil, nil
	}
}

func LegacyDestroyComposeFile(repoRoot string) (string, bool) {
	if fileExists(LegacyCLIComposeFile(repoRoot)) {
		return LegacyCLIComposeFile(repoRoot), true
	}
	if fileExists(LegacyDevcontainerComposeFile(repoRoot)) {
		return LegacyDevcontainerComposeFile(repoRoot), true
	}

	return "", false
}
