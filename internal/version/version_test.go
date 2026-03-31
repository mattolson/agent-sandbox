package version

import (
	"runtime/debug"
	"strings"
	"testing"
	"time"
)

func TestDetectPrefersLDFlags(t *testing.T) {
	reset := overrideBuildGlobals(t)
	defer reset()

	BuildVersion = "v1.2.3"
	BuildCommit = "abcdef123456"
	BuildTime = "2026-03-30T21:45:00Z"
	BuildDirty = "true"

	info := Detect(Options{})
	if info.Source != SourceLDFlags {
		t.Fatalf("unexpected source: %s", info.Source)
	}
	if info.DisplayVersion() != "v1.2.3-dirty" {
		t.Fatalf("unexpected display version: %q", info.DisplayVersion())
	}
}

func TestDetectFallsBackToBuildInfo(t *testing.T) {
	reset := overrideBuildGlobals(t)
	defer reset()

	previous := readBuildInfo
	readBuildInfo = func() (*debug.BuildInfo, bool) {
		return &debug.BuildInfo{
			GoVersion: "go1.26.1",
			Main:      debug.Module{Version: "(devel)"},
			Settings: []debug.BuildSetting{
				{Key: "vcs.revision", Value: "abcdef1234567890"},
				{Key: "vcs.time", Value: "2026-03-30T12:00:00Z"},
				{Key: "vcs.modified", Value: "true"},
			},
		}, true
	}
	t.Cleanup(func() {
		readBuildInfo = previous
	})

	info := Detect(Options{})
	if info.Source != SourceBuildInfo {
		t.Fatalf("unexpected source: %s", info.Source)
	}
	if info.DisplayVersion() != "20260330.120000-abcdef1-dirty" {
		t.Fatalf("unexpected display version: %q", info.DisplayVersion())
	}
}

func TestDetectFallsBackToGit(t *testing.T) {
	reset := overrideBuildGlobals(t)
	defer reset()

	previousBuildInfo := readBuildInfo
	readBuildInfo = func() (*debug.BuildInfo, bool) { return nil, false }
	t.Cleanup(func() {
		readBuildInfo = previousBuildInfo
	})

	previousRunGit := runGit
	runGit = func(_ string, args ...string) (string, error) {
		switch args[0] {
		case "rev-parse":
			return "abcdef1234567890", nil
		case "log":
			return "2026-03-29T11:15:00Z", nil
		case "status":
			return "", nil
		default:
			return "", nil
		}
	}
	t.Cleanup(func() {
		runGit = previousRunGit
	})

	info := Detect(Options{WorkingDir: "/workspace"})
	if info.Source != SourceGit {
		t.Fatalf("unexpected source: %s", info.Source)
	}
	if info.DisplayVersion() != "20260329.111500-abcdef1" {
		t.Fatalf("unexpected display version: %q", info.DisplayVersion())
	}
}

func TestFormatIncludesMetadataLines(t *testing.T) {
	info := Info{
		Commit:     "abcdef1234567890",
		CommitTime: time.Date(2026, time.March, 30, 22, 0, 0, 0, time.UTC),
		Source:     SourceGit,
		GoVersion:  "go1.26.1",
	}

	formatted := info.Format("Agent Sandbox")
	for _, want := range []string{"Agent Sandbox 20260330.220000-abcdef1", "commit: abcdef1234567890", "source: git", "go: go1.26.1"} {
		if !strings.Contains(formatted, want) {
			t.Fatalf("expected formatted output to contain %q, got %q", want, formatted)
		}
	}
}

func overrideBuildGlobals(t *testing.T) func() {
	t.Helper()

	previousVersion := BuildVersion
	previousCommit := BuildCommit
	previousTime := BuildTime
	previousDirty := BuildDirty

	BuildVersion = ""
	BuildCommit = ""
	BuildTime = ""
	BuildDirty = ""

	return func() {
		BuildVersion = previousVersion
		BuildCommit = previousCommit
		BuildTime = previousTime
		BuildDirty = previousDirty
	}
}
