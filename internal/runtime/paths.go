package runtime

import (
	"fmt"
	"os"
	"path/filepath"
)

const (
	AgentSandboxDirName = ".agent-sandbox"
	ModeCLI             = "cli"
	ModeDevcontainer    = "devcontainer"
)

func FindRepoRoot(start string) (string, error) {
	if start == "" {
		var err error
		start, err = os.Getwd()
		if err != nil {
			return "", err
		}
	}

	current, err := filepath.Abs(start)
	if err != nil {
		return "", err
	}

	info, err := os.Stat(current)
	if err == nil && !info.IsDir() {
		current = filepath.Dir(current)
	}

	for {
		if hasRepoMarker(current) {
			return current, nil
		}

		parent := filepath.Dir(current)
		if parent == current {
			return "", fmt.Errorf("repository root not found from %s", start)
		}

		current = parent
	}
}

func hasRepoMarker(dir string) bool {
	for _, marker := range []string{AgentSandboxDirName, ".git", ".devcontainer"} {
		if _, err := os.Stat(filepath.Join(dir, marker)); err == nil {
			return true
		}
	}

	return false
}

func AgentSandboxDir(repoRoot string) string {
	return filepath.Join(repoRoot, AgentSandboxDirName)
}

func ActiveTargetFile(repoRoot string) string {
	return filepath.Join(AgentSandboxDir(repoRoot), "active-target.env")
}

func PolicyDir(repoRoot string) string {
	return filepath.Join(AgentSandboxDir(repoRoot), "policy")
}

func SharedPolicyFile(repoRoot string) string {
	return filepath.Join(PolicyDir(repoRoot), "user.policy.yaml")
}

func UserAgentPolicyFile(repoRoot string, agent string) string {
	return filepath.Join(PolicyDir(repoRoot), "user.agent."+agent+".policy.yaml")
}

func DevcontainerManagedPolicyFile(repoRoot string) string {
	return filepath.Join(PolicyDir(repoRoot), "policy.devcontainer.yaml")
}

func DeriveBaseProjectName(projectPath string) string {
	return filepath.Base(projectPath) + "-sandbox"
}

func ApplyModeSuffix(name string, mode string) string {
	if mode == ModeCLI {
		return name
	}

	return name + "-" + mode
}

func StripModeSuffix(name string, mode string) string {
	if mode == ModeCLI {
		return name
	}

	suffix := "-" + mode
	if len(name) > len(suffix) && name[len(name)-len(suffix):] == suffix {
		return name[:len(name)-len(suffix)]
	}

	return name
}

func DeriveProjectName(projectPath string, mode string) string {
	return ApplyModeSuffix(DeriveBaseProjectName(projectPath), mode)
}
