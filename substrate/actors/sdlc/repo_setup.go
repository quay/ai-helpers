package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
)

func ensureRepo(ctx context.Context) error {
	dir := repoDir()

	if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
		slog.Info("repo already cloned", slog.String("dir", dir))
		return nil
	}

	repoURL := os.Getenv("GITHUB_REPO_URL")
	if repoURL == "" {
		repo := os.Getenv("GITHUB_REPO")
		if repo == "" {
			return fmt.Errorf("GITHUB_REPO or GITHUB_REPO_URL must be set for repo setup")
		}
		token := os.Getenv("GITHUB_TOKEN")
		if token != "" {
			repoURL = fmt.Sprintf("https://x-access-token:%s@github.com/%s.git", token, repo)
		} else {
			repoURL = fmt.Sprintf("https://github.com/%s.git", repo)
		}
	}

	slog.Info("cloning repo", slog.String("dir", dir))

	if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		return fmt.Errorf("creating repo parent dir: %w", err)
	}

	_, err := runCommand(ctx, "", "git", "clone", "--depth", "1", repoURL, dir)
	if err != nil {
		return fmt.Errorf("cloning repo: %w", err)
	}

	slog.Info("repo cloned", slog.String("dir", dir))
	return nil
}
