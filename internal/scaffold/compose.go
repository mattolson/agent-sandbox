package scaffold

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"gopkg.in/yaml.v3"
)

// composeDocument is the YAML shape used for managed compose files.
type composeDocument struct {
	Name     string              `yaml:"name,omitempty"`
	Services composeServices     `yaml:"services,omitempty"`
	Volumes  composeNamedVolumes `yaml:"volumes,omitempty"`
}

const (
	proxySecretMountSource    = "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
	proxySecretMountTarget    = "/run/secrets/agentbox"
	proxySecretSourceEnvName  = "AGENTBOX_SECRET_SOURCE"
	proxySecretSourceEnvValue = "file:/run/secrets/agentbox"

	sharedPolicyMountSource = "../policy/user.policy.yaml"
	sharedPolicyMountTarget = "/etc/agent-sandbox/policy/user.policy.yaml"
)

// composeNamedVolumes preserves top-level named volume ordering and blank-value encoding.
type composeNamedVolumes []composeNamedVolumeEntry

// composeNamedVolumeEntry records one named volume mapping entry.
type composeNamedVolumeEntry struct {
	Name  string
	Value *yaml.Node
}

// composeServices models the compose services block used by managed files.
type composeServices struct {
	Proxy *composeService `yaml:"proxy,omitempty"`
	Agent *composeService `yaml:"agent,omitempty"`
}

// composeService models the subset of service fields the scaffold code reads and writes.
type composeService struct {
	Image       string                      `yaml:"image,omitempty"`
	DependsOn   map[string]composeCondition `yaml:"depends_on,omitempty"`
	CapDrop     []string                    `yaml:"cap_drop,omitempty"`
	CapAdd      []string                    `yaml:"cap_add,omitempty"`
	Volumes     composeVolumes              `yaml:"volumes,omitempty"`
	WorkingDir  string                      `yaml:"working_dir,omitempty"`
	StdinOpen   bool                        `yaml:"stdin_open,omitempty"`
	TTY         bool                        `yaml:"tty,omitempty"`
	Environment []string                    `yaml:"environment,omitempty"`
	Healthcheck *composeHealthcheck         `yaml:"healthcheck,omitempty"`
}

// composeCondition models a depends_on condition entry.
type composeCondition struct {
	Condition string `yaml:"condition,omitempty"`
}

// composeHealthcheck models the subset of healthcheck fields used in templates.
type composeHealthcheck struct {
	Test     []string `yaml:"test,omitempty"`
	Interval string   `yaml:"interval,omitempty"`
	Timeout  string   `yaml:"timeout,omitempty"`
	Retries  int      `yaml:"retries,omitempty"`
}

// composeVolumes preserves service volume entries as either short-form strings or long-syntax mappings.
type composeVolumes []composeVolume

// composeVolume records one service volume sequence entry.
type composeVolume struct {
	node *yaml.Node
}

type composeBindMount struct {
	Source            string
	Target            string
	ReadOnly          bool
	CreateHostPath    bool
	HasCreateHostPath bool
}

func (volumes *composeVolumes) UnmarshalYAML(node *yaml.Node) error {
	if node == nil || node.Kind == 0 || (node.Kind == yaml.ScalarNode && node.Tag == "!!null") {
		*volumes = nil
		return nil
	}
	if node.Kind != yaml.SequenceNode {
		return fmt.Errorf("compose service volumes must be a sequence")
	}

	entries := make(composeVolumes, 0, len(node.Content))
	for _, child := range node.Content {
		if child.Kind != yaml.ScalarNode && child.Kind != yaml.MappingNode {
			return fmt.Errorf("compose service volume entries must be strings or mappings")
		}
		entries = append(entries, composeVolume{node: cloneYAMLNode(child)})
	}

	*volumes = entries
	return nil
}

func (volumes composeVolumes) MarshalYAML() (any, error) {
	node := &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq"}
	for _, volume := range volumes {
		node.Content = append(node.Content, normalizeComposeServiceVolumeNode(volume.node))
	}

	return node, nil
}

func newStringVolume(value string) composeVolume {
	return composeVolume{node: stringNode(value)}
}

func newManagedBindMount(source string, target string, readOnly bool) composeVolume {
	content := []*yaml.Node{
		stringNode("type"),
		stringNode("bind"),
		stringNode("source"),
		stringNode(source),
		stringNode("target"),
		stringNode(target),
	}
	if readOnly {
		content = append(content, stringNode("read_only"), boolNode(true))
	}
	content = append(content,
		stringNode("bind"),
		&yaml.Node{
			Kind: yaml.MappingNode,
			Tag:  "!!map",
			Content: []*yaml.Node{
				stringNode("create_host_path"),
				boolNode(false),
			},
		},
	)

	return composeVolume{
		node: &yaml.Node{
			Kind:    yaml.MappingNode,
			Tag:     "!!map",
			Content: content,
		},
	}
}

func stringNode(value string) *yaml.Node {
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value}
}

func boolNode(value bool) *yaml.Node {
	if value {
		return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!bool", Value: "true"}
	}
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!bool", Value: "false"}
}

func normalizeComposeServiceVolumeNode(node *yaml.Node) *yaml.Node {
	if node == nil || (node.Kind == yaml.ScalarNode && node.Tag == "!!null") {
		return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!null", Value: ""}
	}

	return cloneYAMLNode(node)
}

func (volume composeVolume) stringValue() (string, bool) {
	if volume.node == nil || volume.node.Kind != yaml.ScalarNode {
		return "", false
	}
	return volume.node.Value, true
}

func (volume composeVolume) bindMount() (composeBindMount, bool) {
	if value, ok := volume.stringValue(); ok {
		return parseShortVolume(value)
	}
	if volume.node == nil || volume.node.Kind != yaml.MappingNode {
		return composeBindMount{}, false
	}

	source, sourceOK := mappingStringValue(volume.node, "source")
	target, targetOK := mappingStringValue(volume.node, "target")
	if !sourceOK || !targetOK {
		return composeBindMount{}, false
	}

	readOnly, _ := mappingBoolValue(volume.node, "read_only")
	bindNode := mappingNodeValue(volume.node, "bind")
	createHostPath, hasCreateHostPath := mappingBoolValue(bindNode, "create_host_path")

	return composeBindMount{
		Source:            source,
		Target:            target,
		ReadOnly:          readOnly,
		CreateHostPath:    createHostPath,
		HasCreateHostPath: hasCreateHostPath,
	}, true
}

func (volumes *composeNamedVolumes) UnmarshalYAML(node *yaml.Node) error {
	if node == nil || node.Kind == 0 || (node.Kind == yaml.ScalarNode && node.Tag == "!!null") {
		*volumes = nil
		return nil
	}
	if node.Kind != yaml.MappingNode {
		return fmt.Errorf("compose volumes must be a mapping")
	}

	entries := make(composeNamedVolumes, 0, len(node.Content)/2)
	for i := 0; i+1 < len(node.Content); i += 2 {
		entries = append(entries, composeNamedVolumeEntry{
			Name:  node.Content[i].Value,
			Value: cloneYAMLNode(node.Content[i+1]),
		})
	}

	*volumes = entries
	return nil
}

func (volumes composeNamedVolumes) MarshalYAML() (any, error) {
	node := &yaml.Node{Kind: yaml.MappingNode}
	for _, entry := range volumes {
		node.Content = append(node.Content,
			&yaml.Node{Kind: yaml.ScalarNode, Value: entry.Name},
			normalizeComposeVolumeNode(entry.Value),
		)
	}

	return node, nil
}

func cloneYAMLNode(node *yaml.Node) *yaml.Node {
	if node == nil {
		return nil
	}

	clone := *node
	if len(node.Content) > 0 {
		clone.Content = make([]*yaml.Node, len(node.Content))
		for i, child := range node.Content {
			clone.Content[i] = cloneYAMLNode(child)
		}
	}

	return &clone
}

func normalizeComposeVolumeNode(node *yaml.Node) *yaml.Node {
	if node == nil || (node.Kind == yaml.ScalarNode && node.Tag == "!!null") {
		return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!null", Value: ""}
	}

	return cloneYAMLNode(node)
}

func writeCLIBaseComposeFile(ctx context.Context, params InitParams, env EnvConfig) error {
	doc, header, err := loadComposeTemplate("compose/base.yml")
	if err != nil {
		return err
	}
	ensureProxyService(&doc)
	pinnedProxyImage, err := docker.ResolvePinnedImage(ctx, params.Runner, env.ProxyImage, params.Stderr)
	if err != nil {
		return err
	}

	doc.Name = runtime.ApplyModeSuffix(params.ProjectName, runtime.ModeCLI)
	doc.Services.Proxy.Image = pinnedProxyImage
	ensureCLIBaseProxyRuntimeConfig(&doc)

	return writeComposeDocument(runtime.CLIBaseComposeFile(params.RepoRoot), header, doc)
}

func writeCLIAgentComposeFile(ctx context.Context, params InitParams, env EnvConfig) error {
	doc, header, err := loadComposeTemplate(fmt.Sprintf("%s/cli/agent.yml", params.Agent))
	if err != nil {
		return err
	}
	ensureProxyService(&doc)
	ensureAgentService(&doc)
	pinnedAgentImage, err := docker.ResolvePinnedImage(ctx, params.Runner, env.AgentImage, params.Stderr)
	if err != nil {
		return err
	}

	doc.Services.Agent.Image = pinnedAgentImage
	legacyPolicyVolume := fmt.Sprintf("../policy-cli-%s.yaml:/etc/mitmproxy/policy.yaml:ro", params.Agent)
	doc.Services.Proxy.Volumes = removeVolumeString(doc.Services.Proxy.Volumes, legacyPolicyVolume)
	doc.Services.Proxy.Volumes = ensureManagedBindMount(doc.Services.Proxy.Volumes, fmt.Sprintf("../policy/user.agent.%s.policy.yaml", params.Agent), "/etc/agent-sandbox/policy/user.agent.policy.yaml", true)
	doc.Services.Proxy.Environment = setEnvironmentVar(doc.Services.Proxy.Environment, "AGENTBOX_ACTIVE_AGENT", params.Agent)

	return writeComposeDocument(runtime.CLIAgentComposeFile(params.RepoRoot, params.Agent), header, doc)
}

func writeUserOverrideIfMissing(repoRoot string, outputFile string, templateName string, extraVolumes []string) error {
	if _, err := os.Stat(outputFile); err == nil {
		return nil
	}

	doc, header, err := loadComposeTemplate(templateName)
	if err != nil {
		return err
	}
	ensureAgentService(&doc)
	for _, volume := range extraVolumes {
		doc.Services.Agent.Volumes = ensureVolumeString(doc.Services.Agent.Volumes, volume)
	}

	return writeComposeDocument(outputFile, header, doc)
}

func writeDevcontainerModeComposeFile(repoRoot string, ide string, projectName string) error {
	doc, header, err := loadComposeTemplate("compose/mode.devcontainer.yml")
	if err != nil {
		return err
	}
	ensureAgentService(&doc)
	ensureProxyService(&doc)
	doc.Name = runtime.ApplyModeSuffix(projectName, runtime.ModeDevcontainer)
	doc.Services.Proxy.Volumes = ensureManagedBindMount(doc.Services.Proxy.Volumes, "../policy/policy.devcontainer.yaml", "/etc/agent-sandbox/policy/devcontainer.policy.yaml", true)
	doc.Services.Agent.Volumes = ensureManagedBindMount(doc.Services.Agent.Volumes, "../../.devcontainer", "/workspace/.devcontainer", true)
	if ide == "jetbrains" {
		doc.Services.Agent.Volumes = ensureManagedBindMount(doc.Services.Agent.Volumes, "../../.idea", "/workspace/.idea", true)
		for _, capability := range []string{"DAC_OVERRIDE", "CHOWN", "FOWNER"} {
			doc.Services.Agent.CapAdd = ensureString(doc.Services.Agent.CapAdd, capability)
		}
	} else if ide == "vscode" {
		doc.Services.Agent.Volumes = ensureManagedBindMount(doc.Services.Agent.Volumes, "../../.vscode", "/workspace/.vscode", true)
	}

	return writeComposeDocument(runtime.CLIDevcontainerModeComposeFile(repoRoot), header, doc)
}

func loadComposeTemplate(templateName string) (composeDocument, string, error) {
	data, err := ReadTemplate(templateName)
	if err != nil {
		return composeDocument{}, "", err
	}

	var doc composeDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return composeDocument{}, "", err
	}

	return doc, leadingCommentBlock(string(data)), nil
}

func loadComposeFile(path string) (composeDocument, string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return composeDocument{}, "", err
	}

	var doc composeDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return composeDocument{}, "", err
	}

	return doc, leadingCommentBlock(string(data)), nil
}

func readComposeProjectNameIfExists(path string) (string, error) {
	doc, _, err := loadComposeFile(path)
	if err != nil {
		return "", err
	}

	return doc.Name, nil
}

func readComposeServiceImageIfExists(path string, service string) (string, error) {
	doc, _, err := loadComposeFile(path)
	if err != nil {
		return "", err
	}

	switch service {
	case "proxy":
		if doc.Services.Proxy == nil {
			return "", nil
		}
		return doc.Services.Proxy.Image, nil
	case "agent":
		if doc.Services.Agent == nil {
			return "", nil
		}
		return doc.Services.Agent.Image, nil
	default:
		return "", fmt.Errorf("unsupported compose service %q", service)
	}
}

func ReadComposeServiceImage(path string, service string) (string, error) {
	return readComposeServiceImageIfExists(path, service)
}

func SetComposeServiceImage(path string, service string, image string) (bool, error) {
	doc, header, err := loadComposeFile(path)
	if err != nil {
		return false, err
	}

	changed := false
	switch service {
	case "proxy":
		ensureProxyService(&doc)
		if doc.Services.Proxy.Image != image {
			doc.Services.Proxy.Image = image
			changed = true
		}
	case "agent":
		ensureAgentService(&doc)
		if doc.Services.Agent.Image != image {
			doc.Services.Agent.Image = image
			changed = true
		}
	default:
		return false, fmt.Errorf("unsupported compose service %q", service)
	}

	if !changed {
		return false, nil
	}

	return true, writeComposeDocument(path, header, doc)
}

func setComposeProjectName(path string, projectName string) error {
	doc, header, err := loadComposeFile(path)
	if err != nil {
		return err
	}
	doc.Name = projectName

	return writeComposeDocument(path, header, doc)
}

func ensureCLIBasePolicyRuntimeConfig(repoRoot string) error {
	path := runtime.CLIBaseComposeFile(repoRoot)
	doc, header, err := loadComposeFile(path)
	if err != nil {
		return err
	}
	ensureCLIBaseProxyRuntimeConfig(&doc)

	return writeComposeDocument(path, header, doc)
}

func ensureCLIAgentPolicyRuntimeConfig(repoRoot string, agent string) error {
	path := runtime.CLIAgentComposeFile(repoRoot, agent)
	doc, header, err := loadComposeFile(path)
	if err != nil {
		return err
	}
	ensureProxyService(&doc)
	legacyVolume := fmt.Sprintf("../policy-cli-%s.yaml:/etc/mitmproxy/policy.yaml:ro", agent)
	policyVolume := fmt.Sprintf("../policy/%s:/etc/agent-sandbox/policy/user.agent.policy.yaml:ro", filepath.Base(runtime.UserAgentPolicyFile(repoRoot, agent)))
	doc.Services.Proxy.Volumes = removeVolumeString(doc.Services.Proxy.Volumes, legacyVolume)
	doc.Services.Proxy.Volumes = removeVolumeString(doc.Services.Proxy.Volumes, policyVolume)
	doc.Services.Proxy.Volumes = ensureManagedBindMount(doc.Services.Proxy.Volumes, fmt.Sprintf("../policy/%s", filepath.Base(runtime.UserAgentPolicyFile(repoRoot, agent))), "/etc/agent-sandbox/policy/user.agent.policy.yaml", true)
	doc.Services.Proxy.Environment = setEnvironmentVar(doc.Services.Proxy.Environment, "AGENTBOX_ACTIVE_AGENT", agent)

	return writeComposeDocument(path, header, doc)
}

func writeComposeDocument(path string, header string, doc composeDocument) error {
	body, err := marshalYAML(doc)
	if err != nil {
		return err
	}

	return writeFileIfChanged(path, prependHeader(header, body), 0o644)
}

func ensureProxyService(doc *composeDocument) {
	if doc.Services.Proxy == nil {
		doc.Services.Proxy = &composeService{}
	}
}

func ensureAgentService(doc *composeDocument) {
	if doc.Services.Agent == nil {
		doc.Services.Agent = &composeService{}
	}
}

func ensureCLIBaseProxyRuntimeConfig(doc *composeDocument) {
	ensureProxyService(doc)
	doc.Services.Proxy.Volumes = ensureManagedBindMount(doc.Services.Proxy.Volumes, sharedPolicyMountSource, sharedPolicyMountTarget, true)
	doc.Services.Proxy.Volumes = ensureManagedBindMount(doc.Services.Proxy.Volumes, proxySecretMountSource, proxySecretMountTarget, true)
	doc.Services.Proxy.Environment = setEnvironmentVar(doc.Services.Proxy.Environment, proxySecretSourceEnvName, proxySecretSourceEnvValue)
}

func ensureString(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}

	return append(values, value)
}

func ensureVolumeString(volumes composeVolumes, value string) composeVolumes {
	for _, existing := range volumes {
		if existingValue, ok := existing.stringValue(); ok && existingValue == value {
			return volumes
		}
	}

	return append(volumes, newStringVolume(value))
}

func removeVolumeString(volumes composeVolumes, target string) composeVolumes {
	filtered := make(composeVolumes, 0, len(volumes))
	for _, volume := range volumes {
		if value, ok := volume.stringValue(); ok && value == target {
			continue
		}
		filtered = append(filtered, volume)
	}

	return filtered
}

func ensureManagedBindMount(volumes composeVolumes, source string, target string, readOnly bool) composeVolumes {
	desired := newManagedBindMount(source, target, readOnly)
	filtered := make(composeVolumes, 0, len(volumes)+1)
	inserted := false
	for _, volume := range volumes {
		if mount, ok := volume.bindMount(); ok && mount.Target == target {
			if !inserted {
				filtered = append(filtered, desired)
				inserted = true
			}
			continue
		}
		filtered = append(filtered, volume)
	}

	if !inserted {
		filtered = append(filtered, desired)
	}

	return filtered
}

func parseShortVolume(value string) (composeBindMount, bool) {
	parts := strings.Split(value, ":")
	if len(parts) < 2 {
		return composeBindMount{}, false
	}

	targetIndex := -1
	for index := 1; index < len(parts); index++ {
		if strings.HasPrefix(parts[index], "/") {
			targetIndex = index
			break
		}
	}
	if targetIndex == -1 {
		targetIndex = 1
	}

	mount := composeBindMount{
		Source: strings.Join(parts[:targetIndex], ":"),
		Target: parts[targetIndex],
	}
	for _, option := range parts[targetIndex+1:] {
		if option == "ro" {
			mount.ReadOnly = true
			break
		}
	}

	return mount, true
}

func mappingStringValue(node *yaml.Node, key string) (string, bool) {
	valueNode := mappingNodeValue(node, key)
	if valueNode == nil || valueNode.Kind != yaml.ScalarNode {
		return "", false
	}

	return valueNode.Value, true
}

func mappingBoolValue(node *yaml.Node, key string) (bool, bool) {
	valueNode := mappingNodeValue(node, key)
	if valueNode == nil || valueNode.Kind != yaml.ScalarNode {
		return false, false
	}
	if valueNode.Tag == "!!bool" {
		return strings.EqualFold(valueNode.Value, "true"), true
	}

	switch strings.ToLower(valueNode.Value) {
	case "true", "yes", "on":
		return true, true
	case "false", "no", "off":
		return false, true
	default:
		return false, false
	}
}

func mappingNodeValue(node *yaml.Node, key string) *yaml.Node {
	if node == nil || node.Kind != yaml.MappingNode {
		return nil
	}
	for index := 0; index+1 < len(node.Content); index += 2 {
		if node.Content[index].Value == key {
			return node.Content[index+1]
		}
	}

	return nil
}

func setEnvironmentVar(values []string, name string, value string) []string {
	prefix := name + "="
	filtered := make([]string, 0, len(values)+1)
	for _, entry := range values {
		if !strings.HasPrefix(entry, prefix) {
			filtered = append(filtered, entry)
		}
	}

	return append(filtered, prefix+value)
}
