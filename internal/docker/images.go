package docker

import (
	"context"
	"fmt"
	"io"
	"strings"
)

func ResolvePinnedImage(ctx context.Context, runner Runner, image string, stderr io.Writer) (string, error) {
	if image == "" {
		return "", fmt.Errorf("image reference is required")
	}
	if runner == nil {
		runner = ExecRunner{}
	}
	if stderr == nil {
		stderr = io.Discard
	}

	if strings.HasSuffix(image, ":local") || !strings.Contains(image, "/") {
		return image, nil
	}

	if err := runner.Run(ctx, "docker", []string{"pull", image}, CommandOptions{Stdout: stderr, Stderr: stderr}); err != nil {
		if _, inspectErr := runner.Output(ctx, "docker", []string{"image", "inspect", image}, CommandOptions{Stderr: io.Discard}); inspectErr == nil {
			_, _ = fmt.Fprintf(stderr, "Pull failed but '%s' exists locally; using local image.\n", image)
			return image, nil
		}
		return "", fmt.Errorf("Failed to pull '%s' and no local copy exists.", image)
	}

	output, err := runner.Output(ctx, "docker", []string{"inspect", "--format={{index .RepoDigests 0}}", image}, CommandOptions{Stderr: stderr})
	if err != nil {
		return "", err
	}

	digest := strings.TrimSpace(string(output))
	if digest == "" {
		return "", fmt.Errorf("Failed to resolve digest for '%s'.", image)
	}

	return digest, nil
}
