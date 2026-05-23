package actor

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
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

func (g *GitOpsClient) Push(ctx context.Context, dir, branch, token string) error {
	return gitPush(ctx, dir, branch, token)
}

func (g *GitOpsClient) EnsureRepo(ctx context.Context) error {
	return ensureRepo(ctx)
}

// Git operations functions

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

func injectTokenInURL(remoteURL, token string) string {
	if strings.HasPrefix(remoteURL, "https://") {
		return strings.Replace(remoteURL, "https://", "https://x-access-token:"+token+"@", 1)
	}
	return remoteURL
}

// Repository setup

func ensureRepo(ctx context.Context) error {
	dir := RepoDir()

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
