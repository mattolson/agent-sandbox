package version

import (
	"fmt"
	"os/exec"
	"runtime"
	"runtime/debug"
	"strings"
	"time"
)

var (
	BuildVersion = ""
	BuildCommit  = ""
	BuildTime    = ""
	BuildDirty   = ""
)

// Source identifies where version metadata was discovered.
type Source string

const (
	SourceLDFlags   Source = "ldflags"
	SourceBuildInfo Source = "buildinfo"
	SourceGit       Source = "git"
	SourceDefault   Source = "default"
)

// Info reports the version metadata surfaced by the CLI.
type Info struct {
	Version    string
	Commit     string
	CommitTime time.Time
	Dirty      bool
	GoVersion  string
	Source     Source
}

// Options configures version detection.
type Options struct {
	WorkingDir string
}

var readBuildInfo = debug.ReadBuildInfo
var runGit = func(dir string, args ...string) (string, error) {
	cmdArgs := append([]string{"-C", dir}, args...)
	output, err := exec.Command("git", cmdArgs...).Output()
	if err != nil {
		return "", err
	}

	return strings.TrimSpace(string(output)), nil
}

func Detect(opts Options) Info {
	if info, ok := detectFromLDFlags(); ok {
		return info
	}
	if info, ok := detectFromBuildInfo(); ok {
		return info
	}
	if info, ok := detectFromGit(opts.WorkingDir); ok {
		return info
	}

	return Info{Version: "dev", GoVersion: runtime.Version(), Source: SourceDefault}
}

func detectFromLDFlags() (Info, bool) {
	if BuildVersion == "" && BuildCommit == "" && BuildTime == "" && BuildDirty == "" {
		return Info{}, false
	}

	info := Info{
		Version:   BuildVersion,
		Commit:    BuildCommit,
		Dirty:     BuildDirty == "true",
		GoVersion: runtime.Version(),
		Source:    SourceLDFlags,
	}
	if info.Version == "" {
		info.Version = "dev"
	}
	info.CommitTime = parseTime(BuildTime)

	return info, true
}

func detectFromBuildInfo() (Info, bool) {
	buildInfo, ok := readBuildInfo()
	if !ok {
		return Info{}, false
	}

	settings := map[string]string{}
	for _, setting := range buildInfo.Settings {
		settings[setting.Key] = setting.Value
	}

	info := Info{
		Version:   buildInfo.Main.Version,
		Commit:    settings["vcs.revision"],
		Dirty:     settings["vcs.modified"] == "true",
		GoVersion: buildInfo.GoVersion,
		Source:    SourceBuildInfo,
	}
	if info.Version == "(devel)" {
		info.Version = ""
	}
	info.CommitTime = parseTime(settings["vcs.time"])

	if info.Version == "" && info.Commit == "" {
		return Info{}, false
	}

	return info, true
}

func detectFromGit(dir string) (Info, bool) {
	if dir == "" {
		return Info{}, false
	}

	commit, err := runGit(dir, "rev-parse", "HEAD")
	if err != nil {
		return Info{}, false
	}

	commitTime, err := runGit(dir, "log", "-1", "--format=%cI")
	if err != nil {
		return Info{}, false
	}

	status, err := runGit(dir, "status", "--porcelain", "--untracked-files=no")
	if err != nil {
		return Info{}, false
	}

	return Info{
		Commit:     commit,
		CommitTime: parseTime(commitTime),
		Dirty:      status != "",
		GoVersion:  runtime.Version(),
		Source:     SourceGit,
	}, true
}

func parseTime(value string) time.Time {
	if value == "" {
		return time.Time{}
	}

	for _, layout := range []string{time.RFC3339Nano, time.RFC3339} {
		parsed, err := time.Parse(layout, value)
		if err == nil {
			return parsed.UTC()
		}
	}

	return time.Time{}
}

func (info Info) DisplayVersion() string {
	if info.Version != "" && info.Version != "dev" {
		return withDirtySuffix(info.Version, info.Dirty)
	}

	if info.CommitTime.IsZero() || info.Commit == "" {
		if info.Commit == "" {
			return "dev"
		}

		return withDirtySuffix(info.ShortCommit(), info.Dirty)
	}

	base := fmt.Sprintf("%s-%s", info.CommitTime.UTC().Format("20060102.150405"), info.ShortCommit())
	return withDirtySuffix(base, info.Dirty)
}

func (info Info) ShortCommit() string {
	if len(info.Commit) <= 7 {
		return info.Commit
	}

	return info.Commit[:7]
}

func (info Info) Format(name string) string {
	lines := []string{fmt.Sprintf("%s %s", name, info.DisplayVersion())}
	if info.Commit != "" {
		lines = append(lines, fmt.Sprintf("commit: %s", info.Commit))
	}
	if !info.CommitTime.IsZero() {
		lines = append(lines, fmt.Sprintf("commit-time: %s", info.CommitTime.UTC().Format(time.RFC3339)))
	}
	lines = append(lines, fmt.Sprintf("source: %s", info.Source))
	if info.GoVersion != "" {
		lines = append(lines, fmt.Sprintf("go: %s", info.GoVersion))
	}

	return strings.Join(lines, "\n")
}

func withDirtySuffix(value string, dirty bool) string {
	if !dirty || strings.HasSuffix(value, "-dirty") {
		return value
	}

	return value + "-dirty"
}
