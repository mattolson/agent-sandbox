package cli

import (
	"fmt"

	"github.com/mattolson/agent-sandbox/internal/docker"
	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/scaffold"
	"github.com/spf13/cobra"
)

func newBumpCommand(deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                "bump",
		Short:              "Refresh managed image digests",
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			repoRoot, err := runtime.FindRepoRoot(deps.workingDir)
			if err != nil {
				return err
			}
			if err := runtime.AbortIfUnsupportedLegacyLayout(repoRoot, "bump", "", "", ""); err != nil {
				return err
			}

			layout, ok := runtime.PreferredManagedLayout(repoRoot)
			if !ok {
				return fmt.Errorf("No layered compose layout found at %s. Run 'agentbox init' first.", repoRoot)
			}

			mode := runtime.ModeCLI
			if layout == runtime.LayoutCentralizedDevcontainer {
				mode = runtime.ModeDevcontainer
			}

			stderr := cmd.ErrOrStderr()
			_, _ = fmt.Fprintf(stderr, "Found layered compose files (mode: %s) under %s\n", mode, runtime.ComposeDir(repoRoot))
			_, _ = fmt.Fprintf(stderr, "Checking images for managed %s layers\n", mode)

			if err := bumpComposeService(cmd, deps, runtime.CLIBaseComposeFile(repoRoot), "proxy"); err != nil {
				return err
			}

			existing := map[string]string{}
			for _, layer := range runtime.ExistingManagedAgentLayers(repoRoot) {
				existing[layer.Agent] = layer.File
			}
			for _, agent := range runtime.SupportedAgents() {
				agentFile, ok := existing[agent]
				if !ok {
					_, _ = fmt.Fprintf(stderr, "  %s layer: not initialized, skipping\n", agent)
					continue
				}
				_, _ = fmt.Fprintf(stderr, "  %s layer: %s\n", agent, agentFile)
				if err := bumpComposeService(cmd, deps, agentFile, "agent"); err != nil {
					return err
				}
			}

			_, _ = fmt.Fprintln(stderr, "Bump complete")
			return nil
		},
	}
}

func bumpComposeService(cmd *cobra.Command, deps commandDeps, composeFile string, service string) error {
	stderr := cmd.ErrOrStderr()
	image, err := scaffold.ReadComposeServiceImage(composeFile, service)
	if err != nil {
		return err
	}

	if image == "" {
		_, _ = fmt.Fprintf(stderr, "  %s: no image defined, skipping\n", service)
		return nil
	}

	_, _ = fmt.Fprintf(stderr, "  %s: %s\n", service, image)
	if docker.IsLocalImageRef(image) {
		_, _ = fmt.Fprintln(stderr, "    -> Skipping local image")
		return nil
	}

	baseImage := docker.BaseImageRef(image)
	_, _ = fmt.Fprintf(stderr, "    -> Pulling latest from %s...\n", baseImage)
	newImage, err := docker.ResolvePinnedImage(cmd.Context(), deps.runner, baseImage, stderr)
	if err != nil {
		return err
	}
	if newImage == baseImage && image != baseImage {
		_, _ = fmt.Fprintf(stderr, "    -> Pull failed, keeping current pinned image: %s\n", image)
		return nil
	}

	if newImage == image {
		_, _ = fmt.Fprintln(stderr, "    -> Already at latest digest")
		return nil
	}
	_, _ = fmt.Fprintf(stderr, "    -> Updating to %s\n", newImage)
	_, err = scaffold.SetComposeServiceImage(composeFile, service, newImage)
	return err
}
