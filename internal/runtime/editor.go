package runtime

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/kballard/go-shellquote"
)

type Editor struct {
	Args        []string
	UsesMacOpen bool
}

type LookPathFunc func(string) (string, error)

func ResolveEditor() (Editor, error) {
	env := map[string]string{
		"VISUAL": os.Getenv("VISUAL"),
		"EDITOR": os.Getenv("EDITOR"),
	}

	return ResolveEditorFromEnv(env, exec.LookPath)
}

func ResolveEditorFromEnv(env map[string]string, lookPath LookPathFunc) (Editor, error) {
	if lookPath == nil {
		lookPath = exec.LookPath
	}

	raw := env["VISUAL"]
	if raw == "" {
		raw = env["EDITOR"]
	}
	if raw == "" {
		if openPath, err := lookPath("open"); err == nil {
			raw = openPath
		} else {
			raw = "vi"
		}
	}

	args, err := shellquote.Split(raw)
	if err != nil {
		return Editor{}, fmt.Errorf("parse editor command %q: %w", raw, err)
	}
	if len(args) == 0 {
		return Editor{}, fmt.Errorf("editor command is empty")
	}

	if !strings.ContainsRune(args[0], filepath.Separator) {
		if _, err := lookPath(args[0]); err != nil {
			return Editor{}, fmt.Errorf("editor %q not found: %w", raw, err)
		}
	}

	return Editor{
		Args:        args,
		UsesMacOpen: filepath.Base(args[0]) == "open",
	}, nil
}

func (editor Editor) CommandArgs(file string) []string {
	args := append([]string{}, editor.Args...)
	if editor.UsesMacOpen {
		args = append(args, "--new", "--wait-apps", file)
		return args
	}

	return append(args, file)
}
