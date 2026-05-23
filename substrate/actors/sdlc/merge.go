package main

import (
	"log/slog"
)

func checkMergeReadiness(state *ActorState) bool {
	pr := findActivePR(state)
	if pr == nil {
		return false
	}
	return pr.CIStatus == "passing" && pr.HasApproval && pr.ThreadsOpen == 0
}

func transitionIfMergeReady(state *ActorState) {
	if checkMergeReadiness(state) {
		state.Phase = PhaseMergeReady
		slog.Info("PR is merge-ready", slog.String("ticket", state.Ticket))
	}
}

func transitionOnCIComplete(state *ActorState) {
	pr := findActivePR(state)
	if pr == nil {
		return
	}

	switch state.Phase {
	case PhaseCIWaiting:
		switch pr.CIStatus {
		case "passing":
			if pr.HasApproval && pr.ThreadsOpen == 0 {
				state.Phase = PhaseMergeReady
				slog.Info("CI passed with approval, merge-ready", slog.String("ticket", state.Ticket))
			} else {
				state.Phase = PhaseReviewWaiting
				slog.Info("CI passed, waiting for review", slog.String("ticket", state.Ticket))
			}
		case "failing":
			state.Phase = PhaseCIAnalyzing
			slog.Info("CI failed, starting analysis", slog.String("ticket", state.Ticket))
		}

	case PhaseBackportCIWaiting:
		switch pr.CIStatus {
		case "passing":
			state.Phase = PhaseBackportReviewWaiting
			slog.Info("backport CI passed, waiting for review", slog.String("ticket", state.Ticket))
		case "failing":
			state.Phase = PhaseCIBlocked
			state.SetBlocker("backport_ci_failed", []string{"backport CI failed"})
			slog.Info("backport CI failed", slog.String("ticket", state.Ticket))
		}
	}
}
