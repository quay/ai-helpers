package actor

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"
)

func createPR(ctx context.Context, h *Handler, state *ActorState) error {
	if state.Implementation == nil || state.Implementation.Branch == "" {
		return fmt.Errorf("no implementation branch to create PR from")
	}

	dir := RepoDir()
	token := os.Getenv("GITHUB_TOKEN")
	branch := state.Implementation.Branch

	if token != "" {
		if err := h.git.Push(ctx, dir, branch, token); err != nil {
			return fmt.Errorf("pushing branch: %w", err)
		}
	} else {
		slog.Warn("GITHUB_TOKEN not set, skipping push")
	}

	pr := findActivePR(state)
	repo := ""
	if pr != nil {
		repo = pr.Repo
	}
	if repo == "" {
		repo = os.Getenv("GITHUB_REPO")
	}

	if repo == "" || token == "" {
		slog.Warn("STUB: skipping GitHub PR creation (missing GITHUB_TOKEN or GITHUB_REPO)")
		state.PRs[branch] = &PRState{
			Repo:       repo,
			Number:     0,
			Branch:     branch,
			BaseBranch: "main",
			CIStatus:   "pending",
			Conclusion: "pending",
			CreatedAt:  time.Now(),
		}
		state.Phase = PhaseCIWaiting
		return nil
	}

	prNumber, prURL, err := createGitHubPR(ctx, token, repo, branch, state)
	if err != nil {
		return fmt.Errorf("creating GitHub PR: %w", err)
	}

	state.PRs[branch] = &PRState{
		Repo:       repo,
		Number:     prNumber,
		Branch:     branch,
		BaseBranch: "main",
		URL:        prURL,
		CIStatus:   "pending",
		Conclusion: "pending",
		CreatedAt:  time.Now(),
	}
	state.Phase = PhaseCIWaiting

	slog.Info("PR created", slog.String("ticket", state.Ticket), slog.Int("number", prNumber), slog.String("url", prURL))
	return nil
}

func createGitHubPR(ctx context.Context, token, repo, branch string, state *ActorState) (int, string, error) {
	parts := strings.SplitN(repo, "/", 2)
	if len(parts) != 2 {
		return 0, "", fmt.Errorf("invalid repo format: %s", repo)
	}

	title := fmt.Sprintf("%s: %s", state.Ticket, state.JIRA.Summary)
	body := fmt.Sprintf("## JIRA\n\n[%s](https://issues.redhat.com/browse/%s)\n\n## Summary\n\n%s",
		state.Ticket, state.Ticket, state.Implementation.Plan)

	payload, err := json.Marshal(map[string]any{
		"title": title,
		"body":  body,
		"head":  branch,
		"base":  "main",
		"labels": []string{
			fmt.Sprintf("jira/%s", state.Ticket),
		},
	})
	if err != nil {
		return 0, "", fmt.Errorf("marshaling PR payload: %w", err)
	}

	url := fmt.Sprintf("https://api.github.com/repos/%s/pulls", repo)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(payload))
	if err != nil {
		return 0, "", fmt.Errorf("creating request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, "", fmt.Errorf("GitHub API request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		respBody, _ := io.ReadAll(resp.Body)
		return 0, "", fmt.Errorf("GitHub API returned %d: %s", resp.StatusCode, respBody)
	}

	var result struct {
		Number  int    `json:"number"`
		HTMLURL string `json:"html_url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, "", fmt.Errorf("decoding GitHub response: %w", err)
	}

	return result.Number, result.HTMLURL, nil
}
