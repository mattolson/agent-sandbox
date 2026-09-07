package scaffold

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/runtime"
)

// devcontainerNamePattern matches the first "name" string value in a
// devcontainer template. Every agent template opens with a top-level "name",
// so the first match is the display name shown by VS Code and JetBrains.
var devcontainerNamePattern = regexp.MustCompile(`("name"\s*:\s*")([^"]*)(")`)

// applyDevcontainerName appends the project name to the template's display
// name so IDE window titles distinguish projects, e.g. "Claude Code Sandbox:
// myproject". It edits the template text in place rather than round-tripping
// through a JSON map so the template's key order and indentation survive.
func applyDevcontainerName(templateData []byte, projectName string) ([]byte, error) {
	if projectName == "" {
		return templateData, nil
	}
	loc := devcontainerNamePattern.FindSubmatchIndex(templateData)
	if loc == nil {
		return nil, fmt.Errorf("devcontainer template has no \"name\" field to extend")
	}
	escaped, err := json.Marshal(projectName)
	if err != nil {
		return nil, err
	}
	suffix := string(escaped[1 : len(escaped)-1]) // drop the surrounding quotes
	valueEnd := loc[5]                            // end of the existing name value
	out := append([]byte{}, templateData[:valueEnd]...)
	out = append(out, ": "...)
	out = append(out, suffix...)
	out = append(out, templateData[valueEnd:]...)
	return out, nil
}

func scaffoldDevcontainerUserJSONIfMissing(repoRoot string) error {
	return writeTemplateIfMissing(filepath.Join(repoRoot, ".devcontainer", "devcontainer.user.json"), "devcontainer/devcontainer.user.json")
}

func renderDevcontainerJSON(repoRoot string, agent string, projectName string, outputFile string) error {
	templateData, err := ReadTemplate(filepath.ToSlash(filepath.Join(agent, "devcontainer", "devcontainer.json")))
	if err != nil {
		return err
	}
	templateData, err = applyDevcontainerName(templateData, projectName)
	if err != nil {
		return err
	}
	userFile := filepath.Join(repoRoot, ".devcontainer", "devcontainer.user.json")
	if _, err := os.Stat(userFile); err != nil {
		return writeFileIfChanged(outputFile, ensureTrailingNewline(templateData), 0o644)
	}

	var base any
	if err := json.Unmarshal(templateData, &base); err != nil {
		return err
	}
	userData, err := os.ReadFile(userFile)
	if err != nil {
		return err
	}
	var overlay any
	if err := json.Unmarshal(userData, &overlay); err != nil {
		return err
	}

	merged := mergeJSON(base, overlay)
	body, err := json.MarshalIndent(merged, "", "\t")
	if err != nil {
		return err
	}

	return writeFileIfChanged(outputFile, ensureTrailingNewline(body), 0o644)
}

func cleanupLegacyDevcontainerManagedFiles(repoRoot string) {
	_ = os.Remove(filepath.Join(repoRoot, ".devcontainer", "docker-compose.base.yml"))
	_ = os.Remove(filepath.Join(repoRoot, ".devcontainer", "policy.override.yaml"))
}

// mergeJSON overlays objects recursively and appends arrays so user config extends
// the generated devcontainer template instead of replacing list-valued defaults.
func mergeJSON(base any, overlay any) any {
	switch baseTyped := base.(type) {
	case map[string]any:
		overlayTyped, ok := overlay.(map[string]any)
		if !ok {
			if overlay == nil {
				return base
			}
			return overlay
		}
		merged := make(map[string]any, len(baseTyped))
		for key, value := range baseTyped {
			merged[key] = value
		}
		for key, value := range overlayTyped {
			if existing, ok := merged[key]; ok {
				merged[key] = mergeJSON(existing, value)
			} else {
				merged[key] = value
			}
		}
		return merged
	case []any:
		overlayTyped, ok := overlay.([]any)
		if !ok {
			if overlay == nil {
				return base
			}
			return overlay
		}
		merged := append([]any{}, baseTyped...)
		merged = append(merged, overlayTyped...)
		return merged
	default:
		if overlay == nil {
			return base
		}
		return overlay
	}
}

func ensureTrailingNewline(data []byte) []byte {
	if strings.HasSuffix(string(data), "\n") {
		return data
	}

	return append(data, '\n')
}

func prependHeader(header string, body []byte) []byte {
	if header == "" {
		return body
	}

	return append([]byte(header), body...)
}

func leadingCommentBlock(data string) string {
	lines := strings.SplitAfter(data, "\n")
	var builder strings.Builder
	seenComment := false
	for _, line := range lines {
		trimmed := strings.TrimRight(line, "\r\n")
		if strings.HasPrefix(trimmed, "#") {
			seenComment = true
			builder.WriteString(line)
			continue
		}
		if seenComment && trimmed == "" {
			builder.WriteString(line)
			continue
		}
		break
	}

	return builder.String()
}

func DevcontainerManagedPolicyFile(repoRoot string) string {
	return runtime.DevcontainerManagedPolicyFile(repoRoot)
}
