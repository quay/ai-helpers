package actor

import (
	"context"
	"log/slog"
	"time"
)

func shouldStartChain(phase Phase) bool {
	return phase == PhasePlanning
}

func runImplementationChain(h *Handler, state *ActorState) {
	ctx, cancel := context.WithTimeout(context.Background(), 14*time.Minute)
	defer cancel()

	slog.Info("starting implementation chain", slog.String("ticket", state.Ticket), slog.String("phase", string(state.Phase)))

	if err := h.git.EnsureRepo(ctx); err != nil {
		slog.Error("repo setup failed", slog.String("ticket", state.Ticket), slog.String("error", err.Error()))
		state.SetBlocker("repo_setup_failed", []string{err.Error()})
		state.Phase = PhaseImplementationBlocked
		return
	}

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
			if err := planImplementation(ctx, h, state); err != nil {
				slog.Error("planning failed", slog.String("ticket", state.Ticket), slog.String("error", err.Error()))
				state.SetBlocker("planning_failed", []string{err.Error()})
				state.Phase = PhaseImplementationBlocked
				return
			}

		case PhaseImplementing:
			if err := implementPlan(ctx, h, state); err != nil {
				slog.Error("implementation error", slog.String("ticket", state.Ticket), slog.String("error", err.Error()))
				return
			}
			if state.Phase == PhaseImplementing {
				continue
			}

		case PhasePRCreating:
			if err := createPR(ctx, h, state); err != nil {
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

		h.mu.Lock()
		if err := state.Save(h.statePath); err != nil {
			slog.Error("failed to save state during chain", slog.String("error", err.Error()))
		}
		h.mu.Unlock()

		slog.Info("chain phase transition", slog.String("from", string(prevPhase)), slog.String("to", string(state.Phase)))
	}
}
