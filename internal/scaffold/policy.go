package scaffold

import (
	"os"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"gopkg.in/yaml.v3"
)

// policyDocument is the YAML shape used for managed and user-owned policy files.
type policyDocument struct {
	Services []string `yaml:"services"`
	Domains  []string `yaml:"domains"`
}

func WritePolicyFile(path string, services ...string) error {
	data, err := ReadTemplate("policy.yaml")
	if err != nil {
		return err
	}

	var doc policyDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return err
	}
	doc.Services = compactStrings(services)

	body, err := yaml.Marshal(doc)
	if err != nil {
		return err
	}

	return writeFileIfChanged(path, prependHeader(leadingCommentBlock(string(data)), body), 0o644)
}

func scaffoldUserPolicyFileIfMissing(path string, templateName string) error {
	if _, err := os.Stat(path); err == nil {
		return nil
	}

	data, err := ReadTemplate(templateName)
	if err != nil {
		return err
	}
	return writeFileIfChanged(path, data, 0o644)
}

func writeDevcontainerPolicyFile(path string, ide string) error {
	data, err := ReadTemplate("policy.devcontainer.yaml")
	if err != nil {
		return err
	}
	var doc policyDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return err
	}
	if ide == "none" {
		doc.Services = []string{}
	} else {
		doc.Services = []string{ide}
	}

	body, err := yaml.Marshal(doc)
	if err != nil {
		return err
	}

	return writeFileIfChanged(path, prependHeader(leadingCommentBlock(string(data)), body), 0o644)
}

func compactStrings(values []string) []string {
	result := make([]string, 0, len(values))
	for _, value := range values {
		if value != "" {
			result = append(result, value)
		}
	}

	return result
}

func SharedPolicyFile(repoRoot string) string {
	return runtime.SharedPolicyFile(repoRoot)
}
