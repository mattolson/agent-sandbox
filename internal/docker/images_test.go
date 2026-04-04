package docker

import (
	"bytes"
	"context"
	"errors"
	"reflect"
	"testing"
)

func TestResolvePinnedImageSkipsLocalRefs(t *testing.T) {
	runner := &stubRunner{}
	for _, image := range []string{"agent-sandbox-proxy:local", "local-image"} {
		got, err := ResolvePinnedImage(context.Background(), runner, image, nil)
		if err != nil {
			t.Fatalf("ResolvePinnedImage failed: %v", err)
		}
		if got != image {
			t.Fatalf("unexpected image: got %q want %q", got, image)
		}
	}
	if len(runner.calls) != 0 {
		t.Fatalf("expected no docker calls, got %v", runner.calls)
	}
}

func TestIsLocalImageRef(t *testing.T) {
	for _, image := range []string{"agent-sandbox-proxy:local", "alpine", "local/image"} {
		if image == "local/image" {
			if IsLocalImageRef(image) {
				t.Fatalf("did not expect %q to be treated as local", image)
			}
			continue
		}
		if !IsLocalImageRef(image) {
			t.Fatalf("expected %q to be treated as local", image)
		}
	}
}

func TestBaseImageRefStripsDigest(t *testing.T) {
	if got := BaseImageRef("ghcr.io/foo/bar@sha256:abc123"); got != "ghcr.io/foo/bar" {
		t.Fatalf("unexpected base image: %q", got)
	}
	if got := BaseImageRef("ghcr.io/foo/bar:latest"); got != "ghcr.io/foo/bar:latest" {
		t.Fatalf("unexpected base image: %q", got)
	}
}

func TestResolvePinnedImageReturnsDigestAfterPull(t *testing.T) {
	runner := &stubRunner{outputs: []stubOutput{{stdout: []byte("ghcr.io/foo/bar@sha256:abc123\n")}}}
	got, err := ResolvePinnedImage(context.Background(), runner, "ghcr.io/foo/bar:latest", nil)
	if err != nil {
		t.Fatalf("ResolvePinnedImage failed: %v", err)
	}
	if got != "ghcr.io/foo/bar@sha256:abc123" {
		t.Fatalf("unexpected digest: %q", got)
	}
	assertDockerCalls(t, runner.calls,
		stubCall{method: "run", args: []string{"docker", "pull", "ghcr.io/foo/bar:latest"}},
		stubCall{method: "output", args: []string{"docker", "inspect", "--format={{index .RepoDigests 0}}", "ghcr.io/foo/bar:latest"}},
	)
}

func TestResolvePinnedImageFallsBackToLocalImageAfterPullFailure(t *testing.T) {
	stderr := new(bytes.Buffer)
	runner := &stubRunner{
		runErrs: []error{errors.New("pull failed")},
		outputs: []stubOutput{{stdout: []byte("[]")}},
	}

	got, err := ResolvePinnedImage(context.Background(), runner, "ghcr.io/foo/bar:latest", stderr)
	if err != nil {
		t.Fatalf("ResolvePinnedImage failed: %v", err)
	}
	if got != "ghcr.io/foo/bar:latest" {
		t.Fatalf("unexpected image: %q", got)
	}
	if stderr.String() != "Pull failed but 'ghcr.io/foo/bar:latest' exists locally; using local image.\n" {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
}

func TestResolvePinnedImageFailsWhenNoRemoteOrLocalImageExists(t *testing.T) {
	runner := &stubRunner{
		runErrs: []error{errors.New("pull failed")},
		outputs: []stubOutput{{err: errors.New("inspect failed")}},
	}

	_, err := ResolvePinnedImage(context.Background(), runner, "ghcr.io/foo/bar:latest", nil)
	if err == nil || err.Error() != "Failed to pull 'ghcr.io/foo/bar:latest' and no local copy exists." {
		t.Fatalf("unexpected error: %v", err)
	}
}

type stubRunner struct {
	calls   []stubCall
	runErrs []error
	outputs []stubOutput
}

type stubCall struct {
	method string
	args   []string
}

type stubOutput struct {
	stdout []byte
	err    error
}

func (runner *stubRunner) Run(_ context.Context, name string, args []string, _ CommandOptions) error {
	runner.calls = append(runner.calls, stubCall{method: "run", args: append([]string{name}, args...)})
	if len(runner.runErrs) == 0 {
		return nil
	}
	err := runner.runErrs[0]
	runner.runErrs = runner.runErrs[1:]
	return err
}

func (runner *stubRunner) Output(_ context.Context, name string, args []string, _ CommandOptions) ([]byte, error) {
	runner.calls = append(runner.calls, stubCall{method: "output", args: append([]string{name}, args...)})
	if len(runner.outputs) == 0 {
		return nil, nil
	}
	output := runner.outputs[0]
	runner.outputs = runner.outputs[1:]
	return output.stdout, output.err
}

func assertDockerCalls(t *testing.T, got []stubCall, want ...stubCall) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected docker calls: got %#v want %#v", got, want)
	}
}
