package cli

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/mattolson/agent-sandbox/internal/runtime"
	"github.com/mattolson/agent-sandbox/internal/scaffold"
	"github.com/spf13/cobra"
)

type Prompter interface {
	ReadLine(prompt string) (string, error)
	SelectOption(prompt string, options []string) (string, error)
}

type ioPrompter struct {
	reader *bufio.Reader
	writer io.Writer
}

type initArgs struct {
	Name  string
	Path  string
	Agent string
	Mode  string
	IDE   string
	Batch bool
}

func newInitCommand(opts Options, deps commandDeps) *cobra.Command {
	return &cobra.Command{
		Use:                "init",
		Short:              "Initialize a project sandbox",
		DisableFlagParsing: true,
		Args:               cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			parsed, err := parseInitArgs(args)
			if err != nil {
				return err
			}

			projectPath, err := resolveProjectPath(deps.workingDir, parsed.Path)
			if err != nil {
				return err
			}
			if err := validateInitSelections(parsed); err != nil {
				return err
			}
			if err := runtime.AbortIfUnsupportedLegacyLayout(projectPath, "init", parsed.Agent, parsed.Mode, parsed.IDE); err != nil {
				return err
			}

			prompter := opts.Prompter
			if prompter == nil {
				prompter = newIOPrompter(cmd.InOrStdin(), cmd.ErrOrStderr())
			}

			name, agent, mode, ide, err := completeInitArgs(parsed, projectPath, prompter)
			if err != nil {
				return err
			}

			_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Configuring project at: %s\n", projectPath)
			params := scaffold.InitParams{
				RepoRoot:    projectPath,
				Agent:       agent,
				ProjectName: name,
				IDE:         ide,
				Runner:      opts.Runner,
				Stderr:      cmd.ErrOrStderr(),
				LookupEnv:   opts.LookupEnv,
			}

			switch mode {
			case runtime.ModeCLI:
				if err := scaffold.InitializeCLI(cmd.Context(), params); err != nil {
					return err
				}
				target, _ := runtime.ReadActiveTarget(projectPath)
				target.ActiveAgent = agent
				target.ProjectName = name
				if err := runtime.WriteTargetState(projectPath, target); err != nil {
					return err
				}
			case runtime.ModeDevcontainer:
				if err := scaffold.InitializeDevcontainer(cmd.Context(), params); err != nil {
					return err
				}
				if err := runtime.WriteTargetState(projectPath, runtime.ActiveTarget{ActiveAgent: agent, DevcontainerIDE: ide, ProjectName: name}); err != nil {
					return err
				}
			default:
				return fmt.Errorf("Invalid mode selected: %s", mode)
			}

			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "Use 'agentbox policy config' to view the effective policy and 'agentbox compose config' to view the effective compose stack.")
			return nil
		},
	}
}

func parseInitArgs(args []string) (initArgs, error) {
	parsed := initArgs{}
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--name":
			if i+1 >= len(args) {
				return initArgs{}, fmt.Errorf("Missing value for --name")
			}
			parsed.Name = args[i+1]
			i++
		case "--path":
			if i+1 >= len(args) {
				return initArgs{}, fmt.Errorf("Missing value for --path")
			}
			parsed.Path = args[i+1]
			i++
		case "--agent":
			if i+1 >= len(args) {
				return initArgs{}, fmt.Errorf("Missing value for --agent")
			}
			parsed.Agent = args[i+1]
			i++
		case "--mode":
			if i+1 >= len(args) {
				return initArgs{}, fmt.Errorf("Missing value for --mode")
			}
			parsed.Mode = args[i+1]
			i++
		case "--ide":
			if i+1 >= len(args) {
				return initArgs{}, fmt.Errorf("Missing value for --ide")
			}
			parsed.IDE = args[i+1]
			i++
		case "--batch":
			parsed.Batch = true
		default:
			return initArgs{}, fmt.Errorf("Unknown option: %s", args[i])
		}
	}

	return parsed, nil
}

func resolveProjectPath(workingDir string, value string) (string, error) {
	if value == "" {
		value = "."
	}
	projectPath := value
	if !filepath.IsAbs(projectPath) {
		projectPath = filepath.Join(workingDir, projectPath)
	}
	projectPath, err := filepath.Abs(projectPath)
	if err != nil {
		return "", err
	}

	info, err := os.Stat(projectPath)
	if err != nil || !info.IsDir() {
		return "", fmt.Errorf("Directory does not exist: %s", value)
	}

	return projectPath, nil
}

func validateInitSelections(args initArgs) error {
	if args.Agent != "" {
		if err := runtime.ValidateAgent(args.Agent); err != nil {
			return err
		}
	}
	if args.Mode != "" && args.Mode != runtime.ModeCLI && args.Mode != runtime.ModeDevcontainer {
		return fmt.Errorf("Invalid mode: %s (expected: cli devcontainer)", args.Mode)
	}
	if args.IDE != "" {
		if err := runtime.ValidateDevcontainerIDE(args.IDE); err != nil {
			return err
		}
	}

	return nil
}

func completeInitArgs(args initArgs, projectPath string, prompter Prompter) (name string, agent string, mode string, ide string, err error) {
	defaultName := runtime.DeriveBaseProjectName(projectPath)
	name = args.Name
	if name == "" {
		if args.Batch {
			name = defaultName
		} else {
			name, err = prompter.ReadLine(fmt.Sprintf("Project name [%s]:", defaultName))
			if err != nil {
				return "", "", "", "", err
			}
		}
	}
	if name == "" {
		name = defaultName
	}

	agent = args.Agent
	if agent == "" {
		if args.Batch {
			return "", "", "", "", fmt.Errorf("Missing required option in batch mode: --agent (expected: %s)", runtime.SupportedAgentsDisplay())
		}
		agent, err = prompter.SelectOption("Select agent:", runtime.SupportedAgents())
		if err != nil {
			return "", "", "", "", err
		}
	}

	mode = args.Mode
	if mode == "" {
		if args.Batch {
			return "", "", "", "", fmt.Errorf("Missing required option in batch mode: --mode (expected: cli devcontainer)")
		}
		mode, err = prompter.SelectOption("Select mode:", []string{runtime.ModeCLI, runtime.ModeDevcontainer})
		if err != nil {
			return "", "", "", "", err
		}
	}

	ide = args.IDE
	if mode == runtime.ModeDevcontainer && ide == "" {
		if args.Batch {
			return "", "", "", "", fmt.Errorf("Missing required option in batch mode: --ide (expected: %s)", runtime.SupportedIDEsDisplay())
		}
		ide, err = prompter.SelectOption("Select IDE:", runtime.SupportedIDEs())
		if err != nil {
			return "", "", "", "", err
		}
	}

	return name, agent, mode, ide, nil
}

func newIOPrompter(input io.Reader, output io.Writer) Prompter {
	if input == nil {
		input = os.Stdin
	}
	if output == nil {
		output = io.Discard
	}

	return &ioPrompter{reader: bufio.NewReader(input), writer: output}
}

func (prompter *ioPrompter) ReadLine(prompt string) (string, error) {
	if _, err := fmt.Fprintf(prompter.writer, "%s ", prompt); err != nil {
		return "", err
	}
	line, err := prompter.reader.ReadString('\n')
	if err != nil && err != io.EOF {
		return "", err
	}

	return strings.TrimRight(line, "\r\n"), nil
}

func (prompter *ioPrompter) SelectOption(prompt string, options []string) (string, error) {
	for index, option := range options {
		if _, err := fmt.Fprintf(prompter.writer, "  %d) %s\n", index+1, option); err != nil {
			return "", err
		}
	}

	for {
		if _, err := fmt.Fprintf(prompter.writer, "%s [1] ", prompt); err != nil {
			return "", err
		}
		line, err := prompter.reader.ReadString('\n')
		if err != nil && err != io.EOF {
			return "", err
		}
		line = strings.TrimSpace(line)
		if line == "" {
			return options[0], nil
		}
		selection := 0
		if _, scanErr := fmt.Sscanf(line, "%d", &selection); scanErr == nil && selection >= 1 && selection <= len(options) {
			return options[selection-1], nil
		}
		if _, err := fmt.Fprintln(prompter.writer, "Invalid selection, try again."); err != nil {
			return "", err
		}
	}
}
