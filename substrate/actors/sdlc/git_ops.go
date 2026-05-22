package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func repoDir() string {
	return envOr("REPO_DIR", "/workspace/repo")
}

func gitFetch(ctx context.Context, dir, branch string) error {
	_, err := runCommand(ctx, dir, "git", "fetch", "origin", branch, "--depth", "1")
	return err
}

func gitCheckoutNewBranch(ctx context.Context, dir, branch string) error {
	_, err := runCommand(ctx, dir, "git", "checkout", "-b", branch)
	return err
}

func gitAdd(ctx context.Context, dir string) error {
	_, err := runCommand(ctx, dir, "git", "add", "-A")
	return err
}

func gitCommit(ctx context.Context, dir, message string) error {
	_, err := runCommand(ctx, dir, "git", "commit", "-m", message)
	return err
}

func gitPush(ctx context.Context, dir, branch, token string) error {
	result, err := runCommand(ctx, dir, "git", "remote", "get-url", "origin")
	if err != nil {
		return fmt.Errorf("getting remote URL: %w", err)
	}

	remoteURL := strings.TrimSpace(result.Stdout)
	authURL := injectTokenInURL(remoteURL, token)

	_, err = runCommand(ctx, dir, "git", "push", authURL, branch)
	return err
}

func getFileTree(ctx context.Context, dir string) (string, error) {
	result, err := runCommand(ctx, dir, "find", ".", "-type", "f",
		"-not", "-path", "./.git/*",
		"-not", "-path", "./vendor/*")
	if err != nil {
		return "", err
	}

	lines := strings.Split(result.Stdout, "\n")
	if len(lines) > 500 {
		lines = lines[:500]
	}
	return strings.Join(lines, "\n"), nil
}

func readFileContents(dir string, paths []string) (map[string]string, error) {
	contents := make(map[string]string, len(paths))
	for _, p := range paths {
		data, err := os.ReadFile(filepath.Join(dir, p))
		if err != nil {
			return nil, fmt.Errorf("reading %s: %w", p, err)
		}
		contents[p] = string(data)
	}
	return contents, nil
}

func injectTokenInURL(remoteURL, token string) string {
	if strings.HasPrefix(remoteURL, "https://") {
		return strings.Replace(remoteURL, "https://", "https://x-access-token:"+token+"@", 1)
	}
	return remoteURL
}
