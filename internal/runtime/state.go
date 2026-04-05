package runtime

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/kballard/go-shellquote"
)

// ActiveTarget captures the persisted runtime state for the active agent and related metadata.
type ActiveTarget struct {
	ActiveAgent     string
	DevcontainerIDE string
	ProjectName     string
}

func (target ActiveTarget) Validate() error {
	if target.ActiveAgent == "" {
		return fmt.Errorf("ACTIVE_AGENT is required")
	}
	if target.DevcontainerIDE != "" {
		if err := ValidateDevcontainerIDE(target.DevcontainerIDE); err != nil {
			return err
		}
	}

	return ValidateAgent(target.ActiveAgent)
}

func ReadActiveTarget(repoRoot string) (ActiveTarget, error) {
	data, err := os.ReadFile(ActiveTargetFile(repoRoot))
	if err != nil {
		return ActiveTarget{}, err
	}

	target, err := ParseTargetState(data)
	if err != nil {
		return ActiveTarget{}, err
	}

	if err := target.Validate(); err != nil {
		return ActiveTarget{}, err
	}

	return target, nil
}

func ParseTargetState(data []byte) (ActiveTarget, error) {
	var target ActiveTarget

	scanner := bufio.NewScanner(bytes.NewReader(data))
	for lineNumber := 1; scanner.Scan(); lineNumber++ {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		fields, err := shellquote.Split(line)
		if err != nil {
			return ActiveTarget{}, fmt.Errorf("parse target state line %d: %w", lineNumber, err)
		}
		if len(fields) != 1 {
			return ActiveTarget{}, fmt.Errorf("parse target state line %d: expected one assignment", lineNumber)
		}

		name, value, ok := strings.Cut(fields[0], "=")
		if !ok {
			return ActiveTarget{}, fmt.Errorf("parse target state line %d: expected KEY=value", lineNumber)
		}

		switch name {
		case "ACTIVE_AGENT":
			target.ActiveAgent = value
		case "DEVCONTAINER_IDE":
			target.DevcontainerIDE = value
		case "PROJECT_NAME":
			target.ProjectName = value
		}
	}

	if err := scanner.Err(); err != nil {
		return ActiveTarget{}, err
	}

	return target, nil
}

func WriteTargetState(repoRoot string, target ActiveTarget) error {
	if err := target.Validate(); err != nil {
		return err
	}

	stateFile := ActiveTargetFile(repoRoot)
	tmpFile := stateFile + ".tmp"
	if err := os.MkdirAll(filepath.Dir(stateFile), 0o755); err != nil {
		return err
	}

	var builder strings.Builder
	builder.WriteString("# Managed by agentbox. Tracks the active agent and related runtime metadata for this project.\n")
	builder.WriteString("ACTIVE_AGENT=")
	builder.WriteString(shellquote.Join(target.ActiveAgent))
	builder.WriteString("\n")
	if target.DevcontainerIDE != "" {
		builder.WriteString("DEVCONTAINER_IDE=")
		builder.WriteString(shellquote.Join(target.DevcontainerIDE))
		builder.WriteString("\n")
	}
	if target.ProjectName != "" {
		builder.WriteString("PROJECT_NAME=")
		builder.WriteString(shellquote.Join(target.ProjectName))
		builder.WriteString("\n")
	}

	content := []byte(builder.String())
	if err := os.WriteFile(tmpFile, content, 0o644); err != nil {
		return err
	}
	if existing, err := os.ReadFile(stateFile); err == nil && bytes.Equal(existing, content) {
		_ = os.Remove(tmpFile)
		return nil
	}

	return os.Rename(tmpFile, stateFile)
}
