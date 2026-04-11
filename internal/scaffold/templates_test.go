package scaffold

import (
	"fmt"
	"io/fs"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadTemplateLoadsEmbeddedTemplate(t *testing.T) {
	data, err := ReadTemplate("compose/base.yml")
	if err != nil {
		t.Fatalf("ReadTemplate failed: %v", err)
	}
	if !strings.Contains(string(data), "Managed by agentbox") {
		t.Fatalf("unexpected template contents: %q", string(data))
	}
}

func TestReadTemplateLoadsNestedAgentTemplate(t *testing.T) {
	data, err := ReadTemplate("opencode/cli/agent.yml")
	if err != nil {
		t.Fatalf("ReadTemplate failed: %v", err)
	}
	if !strings.Contains(string(data), "agent-sandbox-opencode") {
		t.Fatalf("unexpected nested template contents: %q", string(data))
	}
}

func TestYAMLTemplatesUseTwoSpaceIndentation(t *testing.T) {
	checkYAMLTemplateIndentation(t, "embedded", TemplatesFS())
}

func checkYAMLTemplateIndentation(t *testing.T, label string, templates fs.FS) {
	t.Helper()

	err := fs.WalkDir(templates, ".", func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		if ext := filepath.Ext(path); ext != ".yml" && ext != ".yaml" {
			return nil
		}

		data, err := fs.ReadFile(templates, path)
		if err != nil {
			return err
		}

		for lineNumber, line := range strings.Split(string(data), "\n") {
			whitespaceWidth := leadingIndentWidth(line)
			if whitespaceWidth == 0 {
				continue
			}

			prefix := line[:whitespaceWidth]
			if strings.Contains(prefix, "\t") {
				return fmt.Errorf("%s:%d uses tab indentation", path, lineNumber+1)
			}
			if strings.Count(prefix, " ")%2 != 0 {
				return fmt.Errorf("%s:%d uses %d leading spaces", path, lineNumber+1, strings.Count(prefix, " "))
			}
		}

		return nil
	})
	if err != nil {
		t.Fatalf("%s YAML template indentation check failed: %v", label, err)
	}
}

func leadingIndentWidth(line string) int {
	width := 0
	for width < len(line) {
		switch line[width] {
		case ' ', '\t':
			width++
		default:
			return width
		}
	}

	return width
}
