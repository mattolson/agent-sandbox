package runtime

import (
	"fmt"
	"slices"
	"strings"
)

var supportedIDEs = []string{"vscode", "jetbrains", "none"}

func SupportedIDEs() []string {
	return slices.Clone(supportedIDEs)
}

func SupportedIDEsDisplay() string {
	return strings.Join(supportedIDEs, " ")
}

func ValidateDevcontainerIDE(ide string) error {
	if slices.Contains(supportedIDEs, ide) {
		return nil
	}

	return fmt.Errorf("Invalid IDE: %s (expected: %s)", ide, SupportedIDEsDisplay())
}
