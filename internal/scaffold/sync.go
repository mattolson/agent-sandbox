package scaffold

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
)

// SyncParams describes the inputs needed to refresh managed runtime files.
type SyncParams struct {
	RepoRoot     string
	Agent        string
	Runner       docker.Runner
	Stderr       io.Writer
	LookupEnv    func(string) string
	PersistState bool
}

func EnsureCLIAgentRuntimeFiles(ctx context.Context, params SyncParams) (runtime.ActiveTarget, error) {
	if err := runtime.ValidateAgent(params.Agent); err != nil {
		return runtime.ActiveTarget{}, err
	}

	target, err := readTargetStateIfExists(params.RepoRoot)
	if err != nil {
		return runtime.ActiveTarget{}, err
	}
	target.ActiveAgent = params.Agent

	env := loadEnvConfig(InitParams{Agent: params.Agent, LookupEnv: params.LookupEnv}, runtime.ModeCLI)
	if err := ensureCLIBasePolicyRuntimeConfigIfExists(params.RepoRoot); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := writeUserOverrideIfMissing(params.RepoRoot, runtime.CLIUserOverrideFile(params.RepoRoot), "compose/user.override.yml", optionalSharedVolumes(env)); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := scaffoldUserPolicyFileIfMissing(runtime.SharedPolicyFile(params.RepoRoot), "user.policy.yaml"); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := scaffoldUserPolicyFileIfMissing(runtime.UserAgentPolicyFile(params.RepoRoot, params.Agent), "user.agent.policy.yaml"); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if _, err := os.Stat(runtime.CLIAgentComposeFile(params.RepoRoot, params.Agent)); errors.Is(err, os.ErrNotExist) {
		if err := writeCLIAgentComposeFile(ctx, InitParams{
			RepoRoot: params.RepoRoot,
			Agent:    params.Agent,
			Runner:   params.Runner,
			Stderr:   params.Stderr,
		}, EnvConfig{AgentImage: defaultAgentImage(params.Agent)}); err != nil {
			return runtime.ActiveTarget{}, err
		}
	} else if err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := ensureCLIAgentPolicyRuntimeConfig(params.RepoRoot, params.Agent); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := writeUserOverrideIfMissing(params.RepoRoot, runtime.CLIUserAgentOverrideFile(params.RepoRoot, params.Agent), "compose/user.agent.override.yml", optionalAgentVolumes(params.Agent, env)); err != nil {
		return runtime.ActiveTarget{}, err
	}

	if params.PersistState {
		if err := runtime.WriteTargetState(params.RepoRoot, target); err != nil {
			return runtime.ActiveTarget{}, err
		}
	}

	return target, nil
}

func EnsureDevcontainerRuntimeFiles(ctx context.Context, params SyncParams) (runtime.ActiveTarget, error) {
	if err := runtime.ValidateAgent(params.Agent); err != nil {
		return runtime.ActiveTarget{}, err
	}

	target, err := readTargetStateIfExists(params.RepoRoot)
	if err != nil {
		return runtime.ActiveTarget{}, err
	}
	target.ActiveAgent = params.Agent
	if target.DevcontainerIDE == "" {
		warnf(params.Stderr, "Devcontainer IDE metadata missing. Defaulting to 'none' for managed file sync.")
		target.DevcontainerIDE = "none"
	}
	if target.ProjectName == "" {
		projectName, err := readComposeProjectNameIfExists(runtime.CLIBaseComposeFile(params.RepoRoot))
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return runtime.ActiveTarget{}, err
		}
		target.ProjectName = runtime.StripModeSuffix(projectName, runtime.ModeDevcontainer)
	}
	if target.ProjectName == "" {
		warnf(params.Stderr, "Project name metadata missing. Falling back to the default derived name.")
		target.ProjectName = runtime.DeriveBaseProjectName(params.RepoRoot)
	}

	proxyImage, err := readComposeServiceImageIfExists(runtime.CLIBaseComposeFile(params.RepoRoot), "proxy")
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return runtime.ActiveTarget{}, err
	}
	if proxyImage == "" {
		proxyImage = defaultProxyImage()
	}
	agentImage, err := readComposeServiceImageIfExists(runtime.CLIAgentComposeFile(params.RepoRoot, params.Agent), "agent")
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return runtime.ActiveTarget{}, err
	}
	if agentImage == "" {
		agentImage = defaultAgentImage(params.Agent)
	}

	if _, err := os.Stat(runtime.CLIBaseComposeFile(params.RepoRoot)); errors.Is(err, os.ErrNotExist) {
		if err := writeCLIBaseComposeFile(ctx, InitParams{
			RepoRoot:    params.RepoRoot,
			Agent:       params.Agent,
			ProjectName: target.ProjectName,
			Runner:      params.Runner,
			Stderr:      params.Stderr,
		}, EnvConfig{ProxyImage: proxyImage}); err != nil {
			return runtime.ActiveTarget{}, err
		}
	} else if err != nil {
		return runtime.ActiveTarget{}, err
	} else if err := setComposeProjectName(runtime.CLIBaseComposeFile(params.RepoRoot), target.ProjectName); err != nil {
		return runtime.ActiveTarget{}, err
	}

	if _, err := os.Stat(runtime.CLIAgentComposeFile(params.RepoRoot, params.Agent)); errors.Is(err, os.ErrNotExist) {
		if err := writeCLIAgentComposeFile(ctx, InitParams{
			RepoRoot: params.RepoRoot,
			Agent:    params.Agent,
			Runner:   params.Runner,
			Stderr:   params.Stderr,
		}, EnvConfig{AgentImage: agentImage}); err != nil {
			return runtime.ActiveTarget{}, err
		}
	} else if err != nil {
		return runtime.ActiveTarget{}, err
	}

	if _, err := EnsureCLIAgentRuntimeFiles(ctx, SyncParams{
		RepoRoot:  params.RepoRoot,
		Agent:     params.Agent,
		Runner:    params.Runner,
		Stderr:    params.Stderr,
		LookupEnv: wrapLookupIgnoringIDE(params.LookupEnv),
	}); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := scaffoldDevcontainerUserJSONIfMissing(params.RepoRoot); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := renderDevcontainerJSON(params.RepoRoot, params.Agent, runtime.DevcontainerJSONFile(params.RepoRoot)); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := writeDevcontainerModeComposeFile(params.RepoRoot, target.DevcontainerIDE, target.ProjectName); err != nil {
		return runtime.ActiveTarget{}, err
	}
	if err := writeDevcontainerPolicyFile(runtime.DevcontainerManagedPolicyFile(params.RepoRoot), target.DevcontainerIDE); err != nil {
		return runtime.ActiveTarget{}, err
	}
	cleanupLegacyDevcontainerManagedFiles(params.RepoRoot)

	if params.PersistState {
		if err := runtime.WriteTargetState(params.RepoRoot, target); err != nil {
			return runtime.ActiveTarget{}, err
		}
	}

	return target, nil
}

func EnsureSharedComposeOverride(repoRoot string, lookupEnv func(string) string) error {
	env := loadEnvConfig(InitParams{LookupEnv: lookupEnv}, runtime.ModeCLI)
	return writeUserOverrideIfMissing(repoRoot, runtime.CLIUserOverrideFile(repoRoot), "compose/user.override.yml", optionalSharedVolumes(env))
}

func EnsureSharedPolicyFile(repoRoot string) error {
	return scaffoldUserPolicyFileIfMissing(runtime.SharedPolicyFile(repoRoot), "user.policy.yaml")
}

func EnsureAgentPolicyFile(repoRoot string, agent string) error {
	if err := runtime.ValidateAgent(agent); err != nil {
		return err
	}

	return scaffoldUserPolicyFileIfMissing(runtime.UserAgentPolicyFile(repoRoot, agent), "user.agent.policy.yaml")
}

func readTargetStateIfExists(repoRoot string) (runtime.ActiveTarget, error) {
	target, err := runtime.ReadActiveTarget(repoRoot)
	if errors.Is(err, os.ErrNotExist) {
		return runtime.ActiveTarget{}, nil
	}
	if err != nil {
		return runtime.ActiveTarget{}, err
	}

	return target, nil
}

func ensureCLIBasePolicyRuntimeConfigIfExists(repoRoot string) error {
	if _, err := os.Stat(runtime.CLIBaseComposeFile(repoRoot)); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}

	return ensureCLIBasePolicyRuntimeConfig(repoRoot)
}

func defaultProxyImage() string {
	return "ghcr.io/mattolson/agent-sandbox-proxy:latest"
}

func defaultAgentImage(agent string) string {
	return fmt.Sprintf("ghcr.io/mattolson/agent-sandbox-%s:latest", agent)
}

func warnf(writer io.Writer, message string) {
	if writer == nil {
		return
	}
	_, _ = fmt.Fprintln(writer, message)
}
