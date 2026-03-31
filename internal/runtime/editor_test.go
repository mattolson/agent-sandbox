package runtime

import (
	"errors"
	"reflect"
	"testing"
)

func TestResolveEditorFromEnvUsesVisualFirst(t *testing.T) {
	editor, err := ResolveEditorFromEnv(map[string]string{
		"VISUAL": "code --wait",
		"EDITOR": "vim",
	}, stubLookPath(map[string]string{"code": "/usr/bin/code"}))
	if err != nil {
		t.Fatalf("ResolveEditorFromEnv failed: %v", err)
	}

	want := []string{"code", "--wait"}
	if !reflect.DeepEqual(editor.Args, want) {
		t.Fatalf("unexpected editor args: got %v want %v", editor.Args, want)
	}
	if editor.UsesMacOpen {
		t.Fatal("did not expect open-specific behavior")
	}
}

func TestResolveEditorFromEnvFallsBackToOpen(t *testing.T) {
	editor, err := ResolveEditorFromEnv(nil, stubLookPath(map[string]string{"open": "/usr/bin/open"}))
	if err != nil {
		t.Fatalf("ResolveEditorFromEnv failed: %v", err)
	}

	want := []string{"/usr/bin/open", "--new", "--wait-apps", "config.yml"}
	if got := editor.CommandArgs("config.yml"); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected open args: got %v want %v", got, want)
	}
}

func TestResolveEditorFromEnvReturnsErrorForMissingBinary(t *testing.T) {
	_, err := ResolveEditorFromEnv(map[string]string{"EDITOR": "missing"}, stubLookPath(nil))
	if err == nil {
		t.Fatal("expected missing editor to fail")
	}
}

func stubLookPath(commands map[string]string) LookPathFunc {
	return func(name string) (string, error) {
		if path, ok := commands[name]; ok {
			return path, nil
		}

		return "", errors.New("not found")
	}
}
