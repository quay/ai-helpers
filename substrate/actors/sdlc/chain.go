package main

import (
	"context"
	"log/slog"
	"time"
)

func shouldStartChain(phase Phase) bool {
	return phase == PhasePlanning
}

func runImplementationChain(state *ActorState) {
	ctx, cancel := context.WithTimeout(context.Background(), 14*time.Minute)
	defer cancel()

	slog.Info("starting implementation chain", slog.String("ticket", state.Ticket), slog.String("phase", string(state.Phase)))

	for {
		select {
		case <-ctx.Done():
			slog.Error("implementation chain timed out", slog.String("ticket", state.Ticket), slog.String("phase", string(state.Phase)))
			state.SetBlocker("chain_timeout", []string{"implementation chain exceeded 14 minute timeout"})
			state.Phase = PhaseImplementationBlocked
			return
		default:
		}

		prevPhase := state.Phase

		switch state.Phase {
		case PhasePlanning:
			if err := planImplementation(ctx, state); err != nil {
				slog.Error("planning failed", slog.String("ticket", state.Ticket), slog.String("error", err.Error()))
				state.SetBlocker("planning_failed", []string{err.Error()})
				state.Phase = PhaseImplementationBlocked
				return
			}

		case PhaseImplementing:
			if err := implementPlan(ctx, state); err != nil {
				slog.Error("implementation error", slog.String("ticket", state.Ticket), slog.String("error", err.Error()))
				return
			}
			if state.Phase == PhaseImplementing {
				continue
			}

		case PhasePRCreating:
			if err := createPR(ctx, state); err != nil {
				slog.Error("PR creation failed", slog.String("ticket", state.Ticket), slog.String("error", err.Error()))
				state.SetBlocker("pr_creation_failed", []string{err.Error()})
				state.Phase = PhaseImplementationBlocked
				return
			}
			return

		case PhaseImplementationBlocked:
			return

		default:
			slog.Warn("unexpected phase in chain", slog.String("phase", string(state.Phase)))
			return
		}

		if err := state.Save(statePath); err != nil {
			slog.Error("failed to save state during chain", slog.String("error", err.Error()))
		}

		slog.Info("chain phase transition", slog.String("from", string(prevPhase)), slog.String("to", string(state.Phase)))
	}
}
