package actor

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/quay/ai-helpers/substrate/internal/envutil"
)

func RepoDir() string {
	return envutil.Or("REPO_DIR", "/tmp/repo")
}

func planImplementation(ctx context.Context, h *Handler, state *ActorState) error {
	if state.JIRA == nil {
		return fmt.Errorf("no JIRA context for planning")
	}

	dir := RepoDir()

	if err := h.git.Fetch(ctx, dir, "main"); err != nil {
		slog.Warn("git fetch failed, continuing with existing state", slog.String("error", err.Error()))
	}

	plan, err := h.claude.Plan(ctx, state.JIRA)
	if err != nil {
		return fmt.Errorf("claude plan failed: %w", err)
	}

	state.Implementation = &ImplementationState{
		Plan:          plan.Plan,
		FilesToModify: plan.FilesToModify,
		TestsNeeded:   plan.TestsNeeded,
	}
	state.Phase = PhaseImplementing

	slog.Info("planning complete", slog.String("ticket", state.Ticket), slog.String("difficulty", plan.Difficulty))
	return nil
}
