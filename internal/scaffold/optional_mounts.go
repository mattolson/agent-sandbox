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
	// wantFile is true when the host path must be a regular file. A
	// directory at that path, such as one Docker created before agentbox
	// disabled host path creation, would be mounted over a file target and
	// break the tool that reads it.
	wantFile bool
}

func homeMount(flag string, home string, relative string, target string, create bool) optionalMount {
	mount := optionalMount{flag: flag, source: "${HOME}/" + relative, target: target, create: create}
	if home != "" {
		mount.hostPath = filepath.Join(home, filepath.FromSlash(relative))
	}
	return mount
}

func homeFileMount(flag string, home string, relative string, target string) optionalMount {
	mount := homeMount(flag, home, relative, target, false)
	mount.wantFile = true
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
		homeFileMount("AGENTBOX_MOUNT_CLAUDE_CONFIG", config.Home, ".claude/CLAUDE.md", "/home/dev/.claude/CLAUDE.md"),
		homeFileMount("AGENTBOX_MOUNT_CLAUDE_CONFIG", config.Home, ".claude/settings.json", "/home/dev/.claude/settings.json"),
	}
}

// prepareOptionalMount creates an agentbox-named directory when it is missing
// and checks that a user-named path exists with the expected type. It returns
// false when the mount should be skipped. An unresolved host path is left to
// docker compose.
func prepareOptionalMount(mount optionalMount, warn io.Writer) (bool, error) {
	if mount.hostPath == "" {
		return true, nil
	}
	if mount.create {
		if err := os.MkdirAll(mount.hostPath, 0o755); err != nil {
			return false, fmt.Errorf("create %s for %s: %w", mount.hostPath, mount.flag, err)
		}
		return true, nil
	}

	info, err := os.Stat(mount.hostPath)
	if errors.Is(err, os.ErrNotExist) {
		skipOptionalMount(warn, mount, "does not exist")
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if mount.wantFile && !info.Mode().IsRegular() {
		skipOptionalMount(warn, mount, "is not a regular file")
		return false, nil
	}
	return true, nil
}

func skipOptionalMount(warn io.Writer, mount optionalMount, reason string) {
	fmt.Fprintf(warn, "Skipping mount of %s: %s %s (%s=true). Fix the path and rerun, or add the mount to the override file by hand.\n", mount.target, mount.hostPath, reason, mount.flag)
}
