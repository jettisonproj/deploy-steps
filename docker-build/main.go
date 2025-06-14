package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"syscall"

	"github.com/spf13/cobra"
)

const (
	// Path to the kaniko executable
	// See https://github.com/GoogleContainerTools/kaniko/blob/main/deploy/Dockerfile#L96
	KANIKO_PATH = "/kaniko/executor"
	// Name of the kaniko executable
	KANIKO_NAME = "executor"
	// String written to the status-path when the image build is skipped
	SKIPPED_STATUS = "Skipped"
)

var (
	mainCmd = &cobra.Command{
		Use:   "docker-build",
		Short: "Build a docker image for a PR or Commit",
		Long: `Builds a docker image for a PR or Commit.
For commits, the docker image will be pushed if the build is successful`,
		RunE: handleMainCmd,
	}
	prCmd = &cobra.Command{
		Use:   "pr",
		Short: "Build a docker image for a PR",
		Long: `Builds a docker image for a PR.
All layers will be built, but the image will not be pushed`,
		RunE: handlePrCmd,
	}
	commitCmd = &cobra.Command{
		Use:   "commit",
		Short: "Build a docker image for a commit",
		Long: `Builds a docker image for a commit.
Builds all layers and pushes the image to a registry if successful`,
		RunE: handleCommitCmd,
	}
)

func configureCmds() {
	prFlags := prCmd.Flags()

	prFlags.String("clone-path", "", "the path to the cloned repo")
	prCmd.MarkFlagRequired("clone-path")

	prFlags.String("dockerfile", "", "the path to the dockerfile to build")
	prCmd.MarkFlagRequired("dockerfile")

	prFlags.String("docker-context-dir", "", "the path to the docker context used for the build")
	prCmd.MarkFlagRequired("docker-context-dir")

	prFlags.String(
		"status-file",
		"",
		"The path to the status file provided by the diff check. If the content is set to Skipped, "+
			"no image build is performed and the command exits successfully")
	prCmd.MarkFlagRequired("status-file")

	commitFlags := commitCmd.Flags()

	commitFlags.String("clone-path", "", "the path to the cloned repo")
	commitCmd.MarkFlagRequired("clone-path")

	commitFlags.String("revision-hash", "", "the revision id (e.g. commit sha hash)")
	commitCmd.MarkFlagRequired("revision-hash")

	commitFlags.String("revision-ref", "", "the ref that will be used locally")
	commitCmd.MarkFlagRequired("revision-ref")

	commitFlags.String("dockerfile", "", "the path to the dockerfile to build")
	commitCmd.MarkFlagRequired("dockerfile")

	commitFlags.String("docker-context-dir", "", "the path to the docker context used for the build")
	commitCmd.MarkFlagRequired("docker-context-dir")

	commitFlags.String("image-registry", "", "The image registry used for pushing images. Set to blank to use docker hub")
	commitCmd.MarkFlagRequired("image-registry")

	commitFlags.String("image-repo", "", "The image repo used for pushing images. Typically the repo name")
	commitCmd.MarkFlagRequired("image-repo")

	commitFlags.String(
		"dockerfile-dir",
		"",
		"The dockerfile-dir is used as a suffix in the image repo. "+
			"This can be blank, but can be set to distinguish images in a monorepo. "+
			"The full image format is: <image-registry><image-repo><dockerfile-dir>:<revision>")
	commitCmd.MarkFlagRequired("dockerfile-dir")

	commitFlags.String(
		"status-file",
		"",
		"The path to the status file provided by the diff check. If the content is set to Skipped, "+
			"no image build is performed and the command exits successfully")
	commitCmd.MarkFlagRequired("status-file")

	mainCmd.AddCommand(prCmd, commitCmd)
}

func handleMainCmd(cmd *cobra.Command, args []string) error {
	return fmt.Errorf("Must specify a subcommand")
}

func handlePrCmd(cmd *cobra.Command, args []string) error {
	// Parse command flags
	prFlags := cmd.Flags()

	clonePath, err := prFlags.GetString("clone-path")
	if err != nil {
		return fmt.Errorf("error processing pr clone-path flag")
	}

	dockerfile, err := prFlags.GetString("dockerfile")
	if err != nil {
		return fmt.Errorf("error processing pr dockerfile flag")
	}

	dockerContextDir, err := prFlags.GetString("docker-context-dir")
	if err != nil {
		return fmt.Errorf("error processing pr docker-context-dir flag")
	}

	statusFile, err := prFlags.GetString("status-file")
	if err != nil {
		return fmt.Errorf("error processing pr status-file flag")
	}

	// Print command flags
	fmt.Printf("PR build with params:\n")
	fmt.Printf("- clonePath: %s\n", clonePath)
	fmt.Printf("- dockerfile: %s\n", dockerfile)
	fmt.Printf("- dockerContextDir: %s\n", dockerContextDir)
	fmt.Printf("- statusFile: %s\n", statusFile)

	// Check status file and skip build if necessary
	skipped, err := isBuildSkipped(statusFile)
	if err != nil {
		return fmt.Errorf("error checking skip status: %s", err)
	}
	if skipped {
		fmt.Println("Build is skipped. Exiting early")
		return nil
	}
	fmt.Println("Continuing build")

	// Build the PR image
	kanikoArgs := []string{
		KANIKO_NAME,
		fmt.Sprintf("--dockerfile=%s/%s", clonePath, dockerfile),
		fmt.Sprintf("--context=dir://%s/%s", clonePath, dockerContextDir),
		"--no-push",
	}
	fmt.Printf(
		"Starting image build for PR using %s with args %s\n",
		KANIKO_PATH,
		kanikoArgs,
	)
	err = syscall.Exec(KANIKO_PATH, kanikoArgs, os.Environ())
	if err != nil {
		panic(err)
	}

	return nil
}

func handleCommitCmd(cmd *cobra.Command, args []string) error {
	// Parse command flags
	commitFlags := cmd.Flags()

	clonePath, err := commitFlags.GetString("clone-path")
	if err != nil {
		return fmt.Errorf("error processing commit clone-path flag")
	}

	revisionHash, err := commitFlags.GetString("revision-hash")
	if err != nil {
		return fmt.Errorf("error processing commit revision-hash flag")
	}

	revisionRef, err := commitFlags.GetString("revision-ref")
	if err != nil {
		return fmt.Errorf("error processing commit revision-ref flag")
	}

	dockerfile, err := commitFlags.GetString("dockerfile")
	if err != nil {
		return fmt.Errorf("error processing commit dockerfile flag")
	}

	dockerContextDir, err := commitFlags.GetString("docker-context-dir")
	if err != nil {
		return fmt.Errorf("error processing commit docker-context-dir flag")
	}

	statusFile, err := commitFlags.GetString("status-file")
	if err != nil {
		return fmt.Errorf("error processing commit status-file flag")
	}

	imageRegistry, err := commitFlags.GetString("image-registry")
	if err != nil {
		return fmt.Errorf("error processing commit image-registry flag")
	}

	imageRepo, err := commitFlags.GetString("image-repo")
	if err != nil {
		return fmt.Errorf("error processing commit image-repo flag")
	}

	dockerfileDir, err := commitFlags.GetString("dockerfile-dir")
	if err != nil {
		return fmt.Errorf("error processing commit dockerfile-dir flag")
	}

	// Print command flags
	fmt.Printf("Commmit build with params:\n")
	fmt.Printf("- clonePath: %s\n", clonePath)
	fmt.Printf("- revisionHash: %s\n", revisionHash)
	fmt.Printf("- revisionRef: %s\n", revisionRef)
	fmt.Printf("- dockerfile: %s\n", dockerfile)
	fmt.Printf("- dockerContextDir: %s\n", dockerContextDir)
	fmt.Printf("- statusFile: %s\n", statusFile)
	fmt.Printf("- imageRegistry: %s\n", imageRegistry)
	fmt.Printf("- imageRepo: %s\n", imageRepo)
	fmt.Printf("- dockerfileDir: %s\n", dockerfileDir)

	// Check status file and skip build if necessary
	skipped, err := isBuildSkipped(statusFile)
	if err != nil {
		return fmt.Errorf("error checking skip status: %s", err)
	}
	if skipped {
		fmt.Println("Build is skipped. Exiting early")
		return nil
	}
	fmt.Println("Continuing build")

	// Build the commit image
	kanikoArgs := []string{
		KANIKO_NAME,
		fmt.Sprintf("--dockerfile=%s/%s", clonePath, dockerfile),
		fmt.Sprintf("--context=dir://%s/%s", clonePath, dockerContextDir),
		fmt.Sprintf(
			"--destination=%s%s%s:%s",
			imageRegistry,
			imageRepo,
			dockerfileDir,
			revisionHash,
		),
	}
	fmt.Printf(
		"Starting image build for commit using %s with args %s\n",
		KANIKO_PATH,
		kanikoArgs,
	)
	err = syscall.Exec(KANIKO_PATH, kanikoArgs, os.Environ())
	if err != nil {
		panic(err)
	}

	return nil
}

func isBuildSkipped(statusFile string) (bool, error) {
	fmt.Println("Checking status file for skipped status")

	bytes, err := os.ReadFile(statusFile)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			fmt.Println("Continuing build due to no status file found")
			return false, nil
		}
		return false, err
	}
	return string(bytes) == SKIPPED_STATUS, nil
}

func main() {
	configureCmds()
	if err := mainCmd.Execute(); err != nil {
		fmt.Printf("error executing command: %s\n", err)
		os.Exit(1)
	}
}
