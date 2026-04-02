package runtime

import "testing"

func TestValidateDevcontainerIDE(t *testing.T) {
	if err := ValidateDevcontainerIDE("vscode"); err != nil {
		t.Fatalf("expected vscode to be valid: %v", err)
	}
	if err := ValidateDevcontainerIDE("invalid"); err == nil {
		t.Fatal("expected invalid ide to fail")
	}
}
