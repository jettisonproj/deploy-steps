package main

import (
	"archive/tar"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"

	"github.com/lmittmann/tint"
	"github.com/spf13/cobra"
)

const (
	// Path to the buildctl executable
	// See https://github.com/moby/buildkit/blob/master/Dockerfile
	BUILDCTL_PATH = "/usr/bin/buildctl-daemonless.sh"
	// Name of the buildctl executable
	BUILDCTL_NAME = "buildctl-daemonless.sh"
	// String written to the status-path when the image build is skipped
	SKIPPED_STATUS = "Skipped"
	// Name of output tar file for the test result artifacts
	ARTIFACTS_TAR_NAME = "artifacts.tar"
	// Name of the target which runs tests and optionally generates artifacts
	TEST_RESULTS_TARGET = "test-results"
	// Name of the target for the integration test image
	TEST_TARGET = "integration-test"
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

	prFlags.String(
		"artifacts-dir",
		"",
		fmt.Sprintf("The directory to place the snapshot of the %s build target", TEST_RESULTS_TARGET))
	prCmd.MarkFlagRequired("artifacts-dir")

	prFlags.Uint(
		"num-artifacts",
		0,
		"The number of expected artifacts. If set to 0, artifacts will not be placed in the artifacts dir")
	prCmd.MarkFlagRequired("num-artifacts")

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

	commitFlags.String(
		"artifacts-dir",
		"",
		fmt.Sprintf("The directory to place the snapshot of the %s build target", TEST_RESULTS_TARGET))
	commitCmd.MarkFlagRequired("artifacts-dir")

	commitFlags.Uint(
		"num-artifacts",
		0,
		"The number of expected artifacts. If set to 0, artifacts will not be placed in the artifacts dir")
	commitCmd.MarkFlagRequired("num-artifacts")

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
		return fmt.Errorf("error processing pr clone-path flag: %s", err)
	}

	dockerfile, err := prFlags.GetString("dockerfile")
	if err != nil {
		return fmt.Errorf("error processing pr dockerfile flag: %s", err)
	}

	dockerContextDir, err := prFlags.GetString("docker-context-dir")
	if err != nil {
		return fmt.Errorf("error processing pr docker-context-dir flag: %s", err)
	}

	statusFile, err := prFlags.GetString("status-file")
	if err != nil {
		return fmt.Errorf("error processing pr status-file flag: %s", err)
	}

	artifactsDir, err := prFlags.GetString("artifacts-dir")
	if err != nil {
		return fmt.Errorf("error processing pr artifacts-dir flag: %s", err)
	}

	numArtifacts, err := prFlags.GetUint("num-artifacts")
	if err != nil {
		return fmt.Errorf("error processing pr num-artifacts flag: %s", err)
	}

	// Done parsing flags. Silence usage when the next error is encountered
	cmd.SilenceUsage = true

	// Print command flags
	slog.Debug("PR build with params:")
	slog.Debug(fmt.Sprintf("- clonePath: %s", clonePath))
	slog.Debug(fmt.Sprintf("- dockerfile: %s", dockerfile))
	slog.Debug(fmt.Sprintf("- dockerContextDir: %s", dockerContextDir))
	slog.Debug(fmt.Sprintf("- statusFile: %s", statusFile))
	slog.Debug(fmt.Sprintf("- artifactsDir: %s", artifactsDir))
	slog.Debug(fmt.Sprintf("- numArtifacts: %d", numArtifacts))

	// Check status file and skip build if necessary
	skipped, err := isBuildSkipped(statusFile)
	if err != nil {
		return fmt.Errorf("error checking skip status: %s", err)
	}
	if skipped {
		slog.Warn("Build is skipped. Exiting early")
		return nil
	}
	slog.Info("Continuing build")

	dockerfileDirPath, dockerfileName := filepath.Split(dockerfile)

	baseBuildArgs := []string{
		BUILDCTL_NAME,
		"build",
		"--frontend",
		"gateway.v0",
		"--opt",
		"source=docker/dockerfile:1",
		"--opt",
		fmt.Sprintf("filename=%s", dockerfileName),
		"--local",
		fmt.Sprintf("context=%s/%s", clonePath, dockerContextDir),
		"--local",
		fmt.Sprintf("dockerfile=%s/%s", clonePath, dockerfileDirPath),
		"--progress",
		"plain",
	}

	// Build the pr test results image
	buildTestResultsImgArgs := slices.Concat(baseBuildArgs, []string{
		"--opt",
		fmt.Sprintf("target=%s", TEST_RESULTS_TARGET),
	})

	if numArtifacts > 0 {
		buildTestResultsImgArgs = append(
			buildTestResultsImgArgs,
			"--output",
			fmt.Sprintf("type=tar,dest=%s/%s", artifactsDir, ARTIFACTS_TAR_NAME),
		)
	}

	slog.Info(fmt.Sprintf(
		"Starting test results image build for pr using %s with args %s",
		BUILDCTL_PATH,
		buildTestResultsImgArgs,
	))

	buildTestResultsImgCmd := exec.Cmd{
		Path:   BUILDCTL_PATH,
		Args:   buildTestResultsImgArgs,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}
	err = buildTestResultsImgCmd.Run()
	if err != nil {
		return fmt.Errorf("Test results image build for pr failed: %s", err)
	}

	// Extract pr test result artifacts if artifacts are expected
	if numArtifacts > 0 {
		err = untar(fmt.Sprintf("%s/%s", artifactsDir, ARTIFACTS_TAR_NAME), artifactsDir)
		if err != nil {
			return fmt.Errorf("Failed to extract pr test result artifacts: %s", err)
		}
	}

	// Build the pr integration test image
	buildTestImgArgs := slices.Concat(baseBuildArgs, []string{
		"--opt",
		fmt.Sprintf("target=%s", TEST_TARGET),
	})

	slog.Info(fmt.Sprintf(
		"Starting integration test image build for pr using %s with args %s",
		BUILDCTL_PATH,
		buildTestImgArgs,
	))

	buildTestImgCmd := exec.Cmd{
		Path:   BUILDCTL_PATH,
		Args:   buildTestImgArgs,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}
	err = buildTestImgCmd.Run()
	if err != nil {
		return fmt.Errorf("Test image build for pr failed: %s", err)
	}

	// Build the PR image
	slog.Info(fmt.Sprintf(
		"Starting image build for PR using %s with args %s",
		BUILDCTL_PATH,
		baseBuildArgs,
	))

	buildImgCmd := exec.Cmd{
		Path:   BUILDCTL_PATH,
		Args:   baseBuildArgs,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}
	err = buildImgCmd.Run()
	if err != nil {
		return fmt.Errorf("Image build for pr failed: %s", err)
	}

	return nil

}

func handleCommitCmd(cmd *cobra.Command, args []string) error {
	// Parse command flags
	commitFlags := cmd.Flags()

	clonePath, err := commitFlags.GetString("clone-path")
	if err != nil {
		return fmt.Errorf("error processing commit clone-path flag: %s", err)
	}

	revisionHash, err := commitFlags.GetString("revision-hash")
	if err != nil {
		return fmt.Errorf("error processing commit revision-hash flag: %s", err)
	}

	revisionRef, err := commitFlags.GetString("revision-ref")
	if err != nil {
		return fmt.Errorf("error processing commit revision-ref flag: %s", err)
	}

	dockerfile, err := commitFlags.GetString("dockerfile")
	if err != nil {
		return fmt.Errorf("error processing commit dockerfile flag: %s", err)
	}

	dockerContextDir, err := commitFlags.GetString("docker-context-dir")
	if err != nil {
		return fmt.Errorf("error processing commit docker-context-dir flag: %s", err)
	}

	statusFile, err := commitFlags.GetString("status-file")
	if err != nil {
		return fmt.Errorf("error processing commit status-file flag: %s", err)
	}

	imageRegistry, err := commitFlags.GetString("image-registry")
	if err != nil {
		return fmt.Errorf("error processing commit image-registry flag: %s", err)
	}

	imageRepo, err := commitFlags.GetString("image-repo")
	if err != nil {
		return fmt.Errorf("error processing commit image-repo flag: %s", err)
	}

	dockerfileDir, err := commitFlags.GetString("dockerfile-dir")
	if err != nil {
		return fmt.Errorf("error processing commit dockerfile-dir flag: %s", err)
	}

	artifactsDir, err := commitFlags.GetString("artifacts-dir")
	if err != nil {
		return fmt.Errorf("error processing commit artifacts-dir flag: %s", err)
	}

	numArtifacts, err := commitFlags.GetUint("num-artifacts")
	if err != nil {
		return fmt.Errorf("error processing commit num-artifacts flag: %s", err)
	}

	// Done parsing flags. Silence usage when the next error is encountered
	cmd.SilenceUsage = true

	// Print command flags
	slog.Debug("Commmit build with params:")
	slog.Debug(fmt.Sprintf("- clonePath: %s", clonePath))
	slog.Debug(fmt.Sprintf("- revisionHash: %s", revisionHash))
	slog.Debug(fmt.Sprintf("- revisionRef: %s", revisionRef))
	slog.Debug(fmt.Sprintf("- dockerfile: %s", dockerfile))
	slog.Debug(fmt.Sprintf("- dockerContextDir: %s", dockerContextDir))
	slog.Debug(fmt.Sprintf("- statusFile: %s", statusFile))
	slog.Debug(fmt.Sprintf("- imageRegistry: %s", imageRegistry))
	slog.Debug(fmt.Sprintf("- imageRepo: %s", imageRepo))
	slog.Debug(fmt.Sprintf("- dockerfileDir: %s", dockerfileDir))
	slog.Debug(fmt.Sprintf("- artifactsDir: %s", artifactsDir))
	slog.Debug(fmt.Sprintf("- numArtifacts: %d", numArtifacts))

	// Check status file and skip build if necessary
	skipped, err := isBuildSkipped(statusFile)
	if err != nil {
		return fmt.Errorf("error checking skip status: %s", err)
	}
	if skipped {
		slog.Warn("Build is skipped. Exiting early")
		return nil
	}
	slog.Info("Continuing build")

	dockerfileDirPath, dockerfileName := filepath.Split(dockerfile)

	baseBuildArgs := []string{
		BUILDCTL_NAME,
		"build",
		"--frontend",
		"gateway.v0",
		"--opt",
		"source=docker/dockerfile:1",
		"--opt",
		fmt.Sprintf("filename=%s", dockerfileName),
		"--local",
		fmt.Sprintf("context=%s/%s", clonePath, dockerContextDir),
		"--local",
		fmt.Sprintf("dockerfile=%s/%s", clonePath, dockerfileDirPath),
		"--progress",
		"plain",
	}

	// Build the commit test results image
	buildTestResultsImgArgs := slices.Concat(baseBuildArgs, []string{
		"--opt",
		fmt.Sprintf("target=%s", TEST_RESULTS_TARGET),
	})

	if numArtifacts > 0 {
		buildTestResultsImgArgs = append(
			buildTestResultsImgArgs,
			"--output",
			fmt.Sprintf("type=tar,dest=%s/%s", artifactsDir, ARTIFACTS_TAR_NAME),
		)
	}

	slog.Info(fmt.Sprintf(
		"Starting test results image build for commit using %s with args %s",
		BUILDCTL_PATH,
		buildTestResultsImgArgs,
	))

	buildTestResultsImgCmd := exec.Cmd{
		Path:   BUILDCTL_PATH,
		Args:   buildTestResultsImgArgs,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}
	err = buildTestResultsImgCmd.Run()
	if err != nil {
		return fmt.Errorf("Test results image build for commit failed: %s", err)
	}

	// Extract commit test result artifacts if artifacts are expected
	if numArtifacts > 0 {
		err = untar(fmt.Sprintf("%s/%s", artifactsDir, ARTIFACTS_TAR_NAME), artifactsDir)
		if err != nil {
			return fmt.Errorf("Failed to extract commit test result artifacts: %s", err)
		}
	}

	// Build the commit integration test image
	buildTestImgArgs := slices.Concat(baseBuildArgs, []string{
		"--opt",
		fmt.Sprintf("target=%s", TEST_TARGET),
		"--output",
		fmt.Sprintf(
			"type=image,name=%s%s%s-%s:%s,push=true",
			imageRegistry,
			imageRepo,
			dockerfileDir,
			TEST_TARGET,
			revisionHash,
		),
	})

	slog.Info(fmt.Sprintf(
		"Starting integration test image build for commit using %s with args %s\n",
		BUILDCTL_PATH,
		buildTestImgArgs,
	))

	buildTestImgCmd := exec.Cmd{
		Path:   BUILDCTL_PATH,
		Args:   buildTestImgArgs,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}
	err = buildTestImgCmd.Run()
	if err != nil {
		return fmt.Errorf("Test image build for commit failed: %s", err)
	}

	// Build the commit image
	buildImgArgs := slices.Concat(baseBuildArgs, []string{
		"--output",
		fmt.Sprintf(
			"type=image,name=%s%s%s:%s,push=true",
			imageRegistry,
			imageRepo,
			dockerfileDir,
			revisionHash,
		),
	})

	slog.Info(fmt.Sprintf(
		"Starting image build for commit using %s with args %s\n",
		BUILDCTL_PATH,
		buildImgArgs,
	))

	buildImgCmd := exec.Cmd{
		Path:   BUILDCTL_PATH,
		Args:   buildImgArgs,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}
	err = buildImgCmd.Run()
	if err != nil {
		return fmt.Errorf("Image build for commit failed: %s", err)
	}

	return nil
}

func isBuildSkipped(statusFile string) (bool, error) {
	slog.Info("Checking status file for skipped status")

	bytes, err := os.ReadFile(statusFile)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			slog.Info("Continuing build due to no status file found")
			return false, nil
		}
		return false, err
	}
	skippedStatus := strings.TrimSpace(string(bytes))
	return skippedStatus == SKIPPED_STATUS, nil
}

func untar(tarPath string, targetDir string) error {
	file, err := os.Open(tarPath)
	if err != nil {
		return fmt.Errorf("Failed to open tar file %s: %s", tarPath, err)
	}
	defer file.Close()

	tarReader := tar.NewReader(file)

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			return nil
		}

		if err != nil {
			return fmt.Errorf("Failed while reading tar file %s: %s", tarPath, err)
		}

		if header == nil {
			slog.Warn("tar file has empty header: %s. Skipping...", "tarPath", tarPath)
			continue
		}

		target := filepath.Join(targetDir, filepath.Clean(header.Name))

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, header.FileInfo().Mode()); err != nil {
				return fmt.Errorf("Error extracting dir %s from tar %s: %s", target, tarPath, err)
			}

		case tar.TypeReg:
			outFile, err := os.OpenFile(target, os.O_CREATE|os.O_RDWR|os.O_TRUNC, header.FileInfo().Mode())
			if err != nil {
				return fmt.Errorf("Error extracting file %s from tar %s: %s", target, tarPath, err)
			}

			// Copy contents from the tar reader to the file
			if _, err := io.Copy(outFile, tarReader); err != nil {
				if closeErr := outFile.Close(); closeErr != nil {
					slog.Warn(fmt.Sprintf("error closing file %s from tar %s after copy error: %s\n", target, tarPath, err))
				}
				return fmt.Errorf("Error copying file %s from tar %s: %s", target, tarPath, err)
			}
			err = outFile.Close()
			if err != nil {
				return fmt.Errorf("Error closing file %s from tar %s: %s\n", target, tarPath, err)
			}
		}
	}
}

func setupLogger() {
	loggerOpts := &tint.Options{
		Level:       slog.LevelDebug,
		ReplaceAttr: setupLogAttrs,
	}
	logger := slog.New(tint.NewTextHandler(os.Stdout, loggerOpts))

	slog.SetDefault(logger)
}

// Set up slog to drop the timestamp since it is already provided by k8s
func setupLogAttrs(groups []string, a slog.Attr) slog.Attr {
	if a.Key == slog.TimeKey {
		return slog.Attr{}
	}
	return a
}

func main() {
	setupLogger()
	configureCmds()
	if err := mainCmd.Execute(); err != nil {
		fmt.Printf("error executing command: %s\n", err)
		os.Exit(1)
	}
}
