package actor

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"unicode"
)

func implementPlan(ctx context.Context, h *Handler, state *ActorState) error {
	if state.JIRA == nil || state.Implementation == nil {
		return fmt.Errorf("missing JIRA context or implementation plan")
	}

	dir := RepoDir()

	if state.Implementation.Branch == "" {
		branch := formatBranchName(state.Ticket, state.JIRA.Summary)
		state.Implementation.Branch = branch
		if err := h.git.CheckoutNewBranch(ctx, dir, branch); err != nil {
			return fmt.Errorf("creating branch: %w", err)
		}
	}

	state.Implementation.AttemptCount++

	plan := &PlanResult{
		Plan:          state.Implementation.Plan,
		FilesToModify: state.Implementation.FilesToModify,
		TestsNeeded:   state.Implementation.TestsNeeded,
	}

	err := h.claude.Implement(ctx, state.JIRA, plan)
	if err != nil {
		state.Implementation.LastError = err.Error()
		state.IncrementRetry("implementation")

		if state.HasExceededRetryLimit("implementation") {
			state.Phase = PhaseImplementationBlocked
			state.SetBlocker("implementation_failed", []string{err.Error()})
			slog.Error("implementation failed, retry limit exceeded",
				slog.String("ticket", state.Ticket),
				slog.Int("attempts", state.Implementation.AttemptCount))
			return nil
		}

		slog.Warn("implementation attempt failed, will retry",
			slog.String("ticket", state.Ticket),
			slog.String("error", err.Error()))
		return nil
	}

	state.Phase = PhasePRCreating
	slog.Info("implementation complete", slog.String("ticket", state.Ticket), slog.String("branch", state.Implementation.Branch))
	return nil
}

func formatBranchName(ticket, summary string) string {
	slug := strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return unicode.ToLower(r)
		}
		if r == ' ' || r == '_' {
			return '-'
		}
		return -1
	}, summary)

	for strings.Contains(slug, "--") {
		slug = strings.ReplaceAll(slug, "--", "-")
	}
	slug = strings.Trim(slug, "-")

	if len(slug) > 40 {
		slug = slug[:40]
		slug = strings.TrimRight(slug, "-")
	}

	return fmt.Sprintf("%s/%s", ticket, slug)
}
