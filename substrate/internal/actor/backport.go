package actor

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
)

func planBackports(h *Handler, state *ActorState) {
	if state.JIRA == nil || len(state.JIRA.TargetVersions) == 0 {
		slog.Info("no target versions, skipping backports", slog.String("ticket", state.Ticket))
		closeTicket(h, state)
		return
	}

	var branches []string
	for _, tv := range state.JIRA.TargetVersions {
		branch := versionToBranch(tv)
		if branch == "" {
			continue
		}
		branches = append(branches, branch)
	}

	if len(branches) == 0 {
		slog.Info("no valid backport branches", slog.String("ticket", state.Ticket))
		closeTicket(h, state)
		return
	}

	state.Backports = &BackportState{
		RequiredBranches: branches,
		Strategy:         make(map[string]string),
	}
	for _, b := range branches {
		state.Backports.Strategy[b] = "cherry-pick-bot"
	}

	slog.Info("backport plan created",
		slog.String("ticket", state.Ticket),
		slog.Any("branches", branches))

	requestNextCherryPick(h, state)
}

func requestNextCherryPick(h *Handler, state *ActorState) {
	if state.Backports == nil {
		closeTicket(h, state)
		return
	}

	for _, branch := range state.Backports.RequiredBranches {
		if isBackportComplete(state, branch) {
			continue
		}
		state.Backports.CurrentBranch = branch
		state.Phase = PhaseBackportBotRequested

		pr := findMainMergedPR(state)
		if pr == nil {
			slog.Error("no merged PR found for cherry-pick request")
			closeTicket(h, state)
			return
		}

		if h.github != nil && pr.Number > 0 {
			comment := fmt.Sprintf("/cherrypick %s", branch)
			ctx := context.Background()
			if err := h.github.PostPRComment(ctx, pr.Repo, pr.Number, comment); err != nil {
				slog.Error("failed to post cherry-pick comment",
					slog.String("branch", branch),
					slog.String("error", err.Error()))
			} else {
				slog.Info("cherry-pick requested",
					slog.String("ticket", state.Ticket),
					slog.String("branch", branch),
					slog.Int("pr", pr.Number))
			}
		} else {
			slog.Warn("STUB: would post /cherrypick comment",
				slog.String("branch", branch))
		}
		return
	}

	closeTicket(h, state)
}

func handleBackportPROpened(state *ActorState, branch string, prNumber int, repo string, headSHA string) {
	if state.Backports == nil || state.Backports.CurrentBranch == "" {
		return
	}

	state.PRs[branch] = &PRState{
		Repo:       repo,
		Number:     prNumber,
		Branch:     branch,
		BaseBranch: state.Backports.CurrentBranch,
		HeadSHA:    headSHA,
		CIStatus:   "pending",
		Conclusion: "pending",
	}

	state.Phase = PhaseBackportCIWaiting
	slog.Info("backport PR opened",
		slog.String("ticket", state.Ticket),
		slog.String("branch", state.Backports.CurrentBranch),
		slog.Int("pr", prNumber))
}

func handleBackportMerged(h *Handler, state *ActorState) {
	if state.Backports == nil {
		return
	}

	state.Backports.CompletedBranches = append(state.Backports.CompletedBranches, state.Backports.CurrentBranch)
	state.Phase = PhaseBackportMerged

	slog.Info("backport merged",
		slog.String("ticket", state.Ticket),
		slog.String("branch", state.Backports.CurrentBranch),
		slog.Int("completed", len(state.Backports.CompletedBranches)),
		slog.Int("total", len(state.Backports.RequiredBranches)))

	requestNextCherryPick(h, state)
}

func isBackportComplete(state *ActorState, branch string) bool {
	for _, b := range state.Backports.CompletedBranches {
		if b == branch {
			return true
		}
	}
	return false
}

func isBackportPhase(phase Phase) bool {
	switch phase {
	case PhaseBackportPlanning, PhaseBackportBotRequested, PhaseBackportCIWaiting,
		PhaseBackportReviewWaiting, PhaseBackportMerged:
		return true
	}
	return false
}

func findMainMergedPR(state *ActorState) *PRState {
	for _, pr := range state.PRs {
		if pr.Conclusion == "merged" && !strings.HasPrefix(pr.BaseBranch, "redhat-") {
			return pr
		}
	}
	return findActivePR(state)
}

func versionToBranch(version string) string {
	parts := strings.SplitN(version, ".", 3)
	if len(parts) < 2 {
		return ""
	}
	return fmt.Sprintf("redhat-%s.%s", parts[0], parts[1])
}
