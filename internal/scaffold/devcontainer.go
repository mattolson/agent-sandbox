package scaffold

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/runtime"
)

func scaffoldDevcontainerUserJSONIfMissing(repoRoot string) error {
	return writeTemplateIfMissing(filepath.Join(repoRoot, ".devcontainer", "devcontainer.user.json"), "devcontainer/devcontainer.user.json")
}

func renderDevcontainerJSON(repoRoot string, agent string, outputFile string) error {
	templateData, err := ReadTemplate(filepath.ToSlash(filepath.Join(agent, "devcontainer", "devcontainer.json")))
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
		merged := make(map[string]any, len(baseTyped)+len(overlayTyped))
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
