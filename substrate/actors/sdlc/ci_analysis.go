package main

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"
)

type CIAnalysisResult struct {
	RootCause   string  `json:"rootCause"`
	Fixable     bool    `json:"fixable"`
	FixApproach string  `json:"fixApproach"`
	Confidence  float64 `json:"confidence"`
}

func shouldStartCIAnalysis(phase Phase) bool {
	return phase == PhaseCIAnalyzing
}

func runCIAnalysisChain(state *ActorState) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	slog.Info("starting CI analysis", slog.String("ticket", state.Ticket))

	pr := findActivePR(state)
	if pr == nil {
		slog.Error("no active PR for CI analysis")
		state.Phase = PhaseCIBlocked
		state.SetBlocker("no_active_pr", []string{"no PR found for CI analysis"})
		return
	}

	failingChecks := collectFailingChecks(pr)
	if len(failingChecks) == 0 {
		slog.Warn("no failing checks found, returning to CIWaiting")
		state.Phase = PhaseCIWaiting
		return
	}

	analysis, err := claudeClient.AnalyzeCI(ctx, state.JIRA, failingChecks)
	if err != nil {
		slog.Error("CI analysis failed", slog.String("error", err.Error()))
		state.Phase = PhaseCIBlocked
		state.SetBlocker("analysis_failed", []string{err.Error()})
		return
	}

	slog.Info("CI analysis complete",
		slog.String("rootCause", analysis.RootCause),
		slog.Bool("fixable", analysis.Fixable),
		slog.Float64("confidence", analysis.Confidence))

	if !analysis.Fixable || analysis.Confidence < 0.7 {
		state.Phase = PhaseCIBlocked
		state.SetBlocker("ci_unfixable", []string{analysis.RootCause, analysis.FixApproach})
		postCIBlockedComment(ctx, state, pr, analysis)
		return
	}

	state.IncrementRetry("ci-fix")
	if state.HasExceededRetryLimit("ci-fix") {
		state.Phase = PhaseCIBlocked
		state.SetBlocker("ci_fix_retry_limit", []string{
			fmt.Sprintf("CI still failing after %d fix attempts", state.Retries.CIFix),
			analysis.RootCause,
		})
		postCIBlockedComment(ctx, state, pr, analysis)
		return
	}

	if err := claudeClient.FixCI(ctx, analysis); err != nil {
		slog.Error("CI fix failed", slog.String("error", err.Error()))
		state.Phase = PhaseCIBlocked
		state.SetBlocker("ci_fix_failed", []string{err.Error()})
		return
	}

	dir := repoDir()
	token := envOr("GITHUB_TOKEN", "")
	if token != "" && state.Implementation != nil && state.Implementation.Branch != "" {
		if err := gitPush(ctx, dir, state.Implementation.Branch, token); err != nil {
			slog.Error("failed to push CI fix", slog.String("error", err.Error()))
		}
	}

	state.Phase = PhaseCIWaiting
	if pr != nil {
		pr.CIStatus = "pending"
	}
	slog.Info("CI fix pushed, returning to CIWaiting",
		slog.String("ticket", state.Ticket),
		slog.Int("attempt", state.Retries.CIFix))
}

func collectFailingChecks(pr *PRState) []string {
	var failing []string
	for name, conclusion := range pr.CheckRuns {
		if conclusion != "success" && conclusion != "neutral" && conclusion != "skipped" {
			failing = append(failing, fmt.Sprintf("%s: %s", name, conclusion))
		}
	}
	return failing
}

func postCIBlockedComment(ctx context.Context, state *ActorState, pr *PRState, analysis *CIAnalysisResult) {
	ghClient := NewGitHubClient()
	if ghClient == nil || pr.Number == 0 {
		return
	}

	var sb strings.Builder
	sb.WriteString("**SDLC Actor: CI blocked**\n\n")
	sb.WriteString(fmt.Sprintf("**Root cause:** %s\n\n", analysis.RootCause))
	if analysis.FixApproach != "" {
		sb.WriteString(fmt.Sprintf("**Approach tried:** %s\n\n", analysis.FixApproach))
	}
	if state.Retries != nil {
		sb.WriteString(fmt.Sprintf("**Fix attempts:** %d/%d\n\n", state.Retries.CIFix, state.Retries.MaxCIFix))
	}
	sb.WriteString("Commands: `/actor-override-ci` to mark CI as passing, `/actor-reset` to retry, `/actor-abandon` to close.\n")

	if err := ghClient.PostPRComment(ctx, pr.Repo, pr.Number, sb.String()); err != nil {
		slog.Error("failed to post CI blocked comment",
			slog.String("error", err.Error()))
	}
}
