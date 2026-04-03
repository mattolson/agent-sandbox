package cli

import (
	"context"
	"io"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/scaffold"
)

type scaffoldRuntimeSyncer struct {
	runner    docker.Runner
	lookupEnv func(string) string
}

func (syncer scaffoldRuntimeSyncer) Sync(ctx context.Context, stack runtime.ComposeStack) error {
	params := scaffold.SyncParams{
		RepoRoot:     stack.RepoRoot,
		Agent:        stack.Target.ActiveAgent,
		Runner:       syncer.runner,
		Stderr:       io.Discard,
		LookupEnv:    syncer.lookupEnv,
		PersistState: true,
	}

	switch stack.Layout {
	case runtime.LayoutCentralizedDevcontainer:
		_, err := scaffold.EnsureDevcontainerRuntimeFiles(ctx, params)
		return err
	case runtime.LayoutLayeredCLI:
		_, err := scaffold.EnsureCLIAgentRuntimeFiles(ctx, params)
		return err
	default:
		return nil
	}
}
