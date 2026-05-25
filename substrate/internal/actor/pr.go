package actor

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"
)

func createPR(ctx context.Context, h *Handler, state *ActorState) error {
	if state.Implementation == nil || state.Implementation.Branch == "" {
		return fmt.Errorf("no implementation branch to create PR from")
	}

	dir := RepoDir()
	branch := state.Implementation.Branch

	if err := h.git.Push(ctx, dir, branch); err != nil {
		return fmt.Errorf("pushing branch: %w", err)
	}

	repo := os.Getenv("GITHUB_REPO")
	if repo == "" {
		slog.Warn("STUB: skipping GitHub PR creation (missing GITHUB_TOKEN or GITHUB_REPO)")
		state.PRs[branch] = &PRState{
			Repo:       repo,
			Branch:     branch,
			CIStatus:   "pending",
			Conclusion: "pending",
			CreatedAt:  time.Now(),
		}
		state.Phase = PhaseCIWaiting
		return nil
	}

	title := fmt.Sprintf("%s: %s", state.Ticket, state.JIRA.Summary)
	body := fmt.Sprintf("## JIRA\n\n[%s](https://issues.redhat.com/browse/%s)\n\n## Summary\n\n%s",
		state.Ticket, state.Ticket, state.Implementation.Plan)

	result, err := runCommand(ctx, dir, "gh", "pr", "create",
		"--title", title,
		"--body", body,
		"--label", fmt.Sprintf("jira/%s", state.Ticket),
		"--json", "number,url")
	if err != nil {
		return fmt.Errorf("gh pr create failed: %w\nstderr: %s", err, result.Stderr)
	}

	var ghResult struct {
		Number int    `json:"number"`
		URL    string `json:"url"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(result.Stdout)), &ghResult); err != nil {
		return fmt.Errorf("parsing gh pr output: %w\nraw: %s", err, result.Stdout)
	}

	state.PRs[branch] = &PRState{
		Repo:       repo,
		Number:     ghResult.Number,
		Branch:     branch,
		URL:        ghResult.URL,
		CIStatus:   "pending",
		Conclusion: "pending",
		CreatedAt:  time.Now(),
	}
	state.Phase = PhaseCIWaiting

	slog.Info("PR created", slog.String("ticket", state.Ticket), slog.Int("number", ghResult.Number), slog.String("url", ghResult.URL))
	return nil
}
