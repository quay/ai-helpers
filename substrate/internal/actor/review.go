package actor

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/quay/ai-helpers/substrate/internal/envutil"
)

type FeedbackCategory struct {
	Blocking       []ReviewComment
	Suggestions    []ReviewComment
	Clarifications []ReviewComment
}

func shouldStartReviewHandling(phase Phase) bool {
	return phase == PhaseAddressingFeedback
}

func runReviewFeedbackChain(h *Handler, state *ActorState) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	pr := findActivePR(state)
	if pr == nil {
		slog.Error("no active PR for review feedback")
		return
	}

	slog.Info("addressing review feedback", slog.String("ticket", state.Ticket))

	err := h.claude.AddressFeedback(ctx, state.JIRA, pr)
	if err != nil {
		slog.Error("failed to address feedback", slog.String("error", err.Error()))
		state.IncrementRetry("review-response")
		if state.HasExceededRetryLimit("review-response") {
			state.Phase = PhaseImplementationBlocked
			state.SetBlocker("review_response_failed", []string{err.Error()})
			return
		}
		return
	}

	dir := RepoDir()
	token := envutil.Or("GITHUB_TOKEN", "")
	if token != "" && state.Implementation != nil && state.Implementation.Branch != "" {
		if err := h.git.Push(ctx, dir, state.Implementation.Branch, token); err != nil {
			slog.Error("failed to push feedback changes", slog.String("error", err.Error()))
		}
	}

	state.Phase = PhaseCIWaiting
	if pr != nil {
		pr.CIStatus = "pending"
	}
	slog.Info("feedback addressed, returning to CIWaiting", slog.String("ticket", state.Ticket))
}

func handleClarificationReply(h *Handler, state *ActorState, commentBody string) (string, error) {
	if state.Phase != PhaseClarificationNeeded {
		return "ignored (not in clarification phase)", nil
	}

	resolved, err := h.claude.CheckClarification(context.Background(), commentBody)
	if err != nil {
		return "", fmt.Errorf("checking clarification: %w", err)
	}

	if resolved {
		state.Phase = PhaseAddressingFeedback
		state.ClearBlocker()
		return "clarification resolved, addressing feedback", nil
	}

	return "clarification not yet resolved", nil
}

func categorizeAndTransition(h *Handler, state *ActorState, review *parsedReview) {
	pr := findActivePR(state)
	if pr == nil {
		return
	}

	pr.Reviews = append(pr.Reviews, ReviewRecord{
		ID:          review.ID,
		Reviewer:    review.User,
		State:       review.State,
		SubmittedAt: time.Now(),
		Body:        review.Body,
		Comments:    review.Comments,
	})

	if review.State != "changes_requested" {
		return
	}

	state.Phase = PhaseChangesRequested

	if len(review.Comments) == 0 {
		state.Phase = PhaseAddressingFeedback
		return
	}

	hasAmbiguous := false
	for _, c := range review.Comments {
		if isAmbiguous(c.Body) {
			hasAmbiguous = true
			break
		}
	}

	if hasAmbiguous {
		state.Phase = PhaseClarificationNeeded
		state.SetBlocker("awaiting_clarification", []string{"review contains ambiguous comments requiring clarification"})

		if h.github != nil && pr.Number > 0 {
			if err := h.github.PostPRComment(context.Background(), pr.Repo, pr.Number,
				"I have questions about some review comments. Could you clarify the ambiguous feedback?"); err != nil {
				slog.Error("failed to post clarification request", slog.String("error", err.Error()))
			}
		}
	} else {
		state.Phase = PhaseAddressingFeedback
	}

	pr.ThreadsOpen += len(review.Comments)
}

func isAmbiguous(body string) bool {
	lower := strings.ToLower(body)
	ambiguousSignals := []string{"what about", "have you considered", "thoughts on", "not sure about"}
	for _, signal := range ambiguousSignals {
		if strings.Contains(lower, signal) {
			return true
		}
	}
	return false
}
