package actor

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
)

// GitOpsClient implements git operations for the actor
type GitOpsClient struct {
	repoDir string
}

func NewGitOpsClient(repoDir string) *GitOpsClient {
	return &GitOpsClient{repoDir: repoDir}
}

func (g *GitOpsClient) Fetch(ctx context.Context, dir, branch string) error {
	return gitFetch(ctx, dir, branch)
}

func (g *GitOpsClient) CheckoutNewBranch(ctx context.Context, dir, branch string) error {
	return gitCheckoutNewBranch(ctx, dir, branch)
}

func (g *GitOpsClient) Add(ctx context.Context, dir string) error {
	return gitAdd(ctx, dir)
}

func (g *GitOpsClient) Commit(ctx context.Context, dir, message string) error {
	return gitCommit(ctx, dir, message)
}

func (g *GitOpsClient) Push(ctx context.Context, dir, branch string) error {
	return gitPush(ctx, dir, branch)
}

func (g *GitOpsClient) EnsureRepo(ctx context.Context) error {
	return ensureRepo(ctx)
}

// Git operations functions

func gitFetch(ctx context.Context, dir, branch string) error {
	args := []string{"fetch", "origin", "--depth", "1"}
	if branch != "" {
		args = append(args, branch)
	}
	_, err := runCommand(ctx, dir, "git", args...)
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

func gitPush(ctx context.Context, dir, branch string) error {
	_, err := runCommand(ctx, dir, "git", "push", "-u", "origin", branch)
	return err
}

// Repository setup

func ensureRepo(ctx context.Context) error {
	dir := RepoDir()

	if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
		slog.Info("repo already cloned", slog.String("dir", dir))
		return nil
	}

	repo := os.Getenv("GITHUB_REPO")
	if repo == "" {
		return fmt.Errorf("GITHUB_REPO must be set for repo setup")
	}

	slog.Info("cloning repo", slog.String("dir", dir), slog.String("repo", repo))

	if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		return fmt.Errorf("creating repo parent dir: %w", err)
	}

	token := os.Getenv("GITHUB_TOKEN")
	var repoURL string
	if token != "" {
		repoURL = fmt.Sprintf("https://x-access-token:%s@github.com/%s.git", token, repo)
	} else {
		repoURL = fmt.Sprintf("https://github.com/%s.git", repo)
	}

	_, err := runCommand(ctx, "", "git", "clone", "--depth", "1", repoURL, dir)
	if err != nil {
		return fmt.Errorf("cloning repo: %w", err)
	}

	slog.Info("repo cloned", slog.String("dir", dir))
	return nil
}
