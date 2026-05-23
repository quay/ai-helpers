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
	if state.Phase != PhaseCIWaiting {
		return
	}
	pr := findActivePR(state)
	if pr == nil {
		return
	}
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
}
