package runtime

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"strings"

	"github.com/kballard/go-shellquote"
)

type ActiveTarget struct {
	ActiveAgent     string
	DevcontainerIDE string
	ProjectName     string
}

func (target ActiveTarget) Validate() error {
	if target.ActiveAgent == "" {
		return fmt.Errorf("ACTIVE_AGENT is required")
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
