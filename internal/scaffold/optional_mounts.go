package scaffold

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// optionalMount is an opt-in host mount that an AGENTBOX_* environment
// variable seeds into a user-owned override scaffold.
type optionalMount struct {
	// flag is the environment variable that enabled the mount.
	flag string
	// source is the compose-side source: ${HOME}/... or a path relative to
	// .agent-sandbox/compose/.
	source string
	// target is the container path.
	target string
	// hostPath is the resolved host path, or "" when HOME is unknown.
	hostPath string
	// create is true for directories agentbox names and may create when
	// missing. User-named paths are never created; a missing one skips the
	// mount instead of letting Docker replace it with an empty directory.
	create bool
}

func homeMount(flag string, home string, relative string, target string, create bool) optionalMount {
	mount := optionalMount{flag: flag, source: "${HOME}/" + relative, target: target, create: create}
	if home != "" {
		mount.hostPath = filepath.Join(home, filepath.FromSlash(relative))
	}
	return mount
}

func workspaceMount(flag string, repoRoot string, name string, create bool) optionalMount {
	return optionalMount{
		flag:     flag,
		source:   "../../" + name,
		target:   "/workspace/" + name,
		hostPath: filepath.Join(repoRoot, name),
		create:   create,
	}
}

// optionalSharedMounts lists the opt-in mounts for the shared override file.
func optionalSharedMounts(repoRoot string, config EnvConfig) []optionalMount {
	mounts := make([]optionalMount, 0, 5)
	if config.EnableShellCustomizations {
		mounts = append(mounts, homeMount("AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS", config.Home, ".config/agent-sandbox/shell.d", "/home/dev/.config/agent-sandbox/shell.d", true))
	}
	if config.EnableDotfiles {
		mounts = append(mounts, homeMount("AGENTBOX_ENABLE_DOTFILES", config.Home, ".config/agent-sandbox/dotfiles", "/home/dev/.dotfiles", true))
	}
	if config.MountGitReadonly {
		mounts = append(mounts, workspaceMount("AGENTBOX_MOUNT_GIT_READONLY", repoRoot, ".git", false))
	}
	if config.MountIdeaReadonly {
		mounts = append(mounts, workspaceMount("AGENTBOX_MOUNT_IDEA_READONLY", repoRoot, ".idea", true))
	}
	if config.MountVSCodeReadonly {
		mounts = append(mounts, workspaceMount("AGENTBOX_MOUNT_VSCODE_READONLY", repoRoot, ".vscode", true))
	}

	return mounts
}

// optionalAgentMounts lists the opt-in mounts for one agent's override file.
func optionalAgentMounts(agent string, config EnvConfig) []optionalMount {
	if agent != "claude" || !config.MountClaudeConfig {
		return nil
	}

	return []optionalMount{
		homeMount("AGENTBOX_MOUNT_CLAUDE_CONFIG", config.Home, ".claude/CLAUDE.md", "/home/dev/.claude/CLAUDE.md", false),
		homeMount("AGENTBOX_MOUNT_CLAUDE_CONFIG", config.Home, ".claude/settings.json", "/home/dev/.claude/settings.json", false),
	}
}

// prepareOptionalMount creates an agentbox-named directory when it is missing
// and checks that a user-named path exists. It returns false when the mount
// should be skipped. An unresolved host path is left to docker compose.
func prepareOptionalMount(mount optionalMount, warn io.Writer) (bool, error) {
	if mount.hostPath == "" {
		return true, nil
	}
	if mount.create {
		return true, os.MkdirAll(mount.hostPath, 0o755)
	}

	_, err := os.Stat(mount.hostPath)
	if err == nil {
		return true, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return false, err
	}
	fmt.Fprintf(warn, "Skipping mount of %s: %s does not exist (%s=true). Create it and rerun, or add the mount to the override file by hand.\n", mount.target, mount.hostPath, mount.flag)
	return false, nil
}
