package actor

import (
	"fmt"
	"strings"
)

// processActorCommand handles /actor-* commands posted in issue/PR comments.
// Returns a response message and error if the command fails.
func processActorCommand(state *ActorState, command, args string) (string, error) {
	switch command {
	case "/actor-status":
		return handleActorStatus(state)
	case "/actor-reset":
		return handleActorReset(state)
	case "/actor-skip":
		return handleActorSkip(state, args)
	case "/actor-continue":
		return handleActorContinue(state)
	case "/actor-override-ci":
		return handleActorOverrideCI(state)
	case "/actor-abandon":
		return handleActorAbandon(state)
	case "/actor-merge":
		return handleActorMerge(state)
	default:
		return "", fmt.Errorf("unknown command: %s", command)
	}
}

func handleActorStatus(state *ActorState) (string, error) {
	var sb strings.Builder
	sb.WriteString("**SDLC Actor Status**\n\n")
	sb.WriteString(fmt.Sprintf("- **Phase**: %s\n", state.Phase))

	if state.Retries != nil {
		sb.WriteString("- **Retries**:\n")
		sb.WriteString(fmt.Sprintf("  - Implementation: %d/%d\n", state.Retries.Implementation, state.Retries.MaxImplementation))
		sb.WriteString(fmt.Sprintf("  - CI Fix: %d/%d\n", state.Retries.CIFix, state.Retries.MaxCIFix))
		sb.WriteString(fmt.Sprintf("  - Review Response: %d/%d\n", state.Retries.ReviewResponse, state.Retries.MaxReviewResponse))
		sb.WriteString(fmt.Sprintf("  - Backport: %d/%d\n", state.Retries.BackportAttempt, state.Retries.MaxBackportAttempt))
	}

	if state.Blockers != nil {
		sb.WriteString("- **Blockers**:\n")
		sb.WriteString(fmt.Sprintf("  - Reason: %s\n", state.Blockers.Reason))
		if len(state.Blockers.Details) > 0 {
			sb.WriteString("  - Details:\n")
			for _, detail := range state.Blockers.Details {
				sb.WriteString(fmt.Sprintf("    - %s\n", detail))
			}
		}
	}

	if pr := state.GetMainPR(); pr != nil {
		sb.WriteString(fmt.Sprintf("- **Active PR**: #%d\n", pr.Number))
		sb.WriteString(fmt.Sprintf("  - CI Status: %s\n", pr.CIStatus))
		sb.WriteString(fmt.Sprintf("  - Has Approval: %v\n", pr.HasApproval))
	}

	return sb.String(), nil
}

func handleActorReset(state *ActorState) (string, error) {
	oldPhase := state.Phase
	activePhase, err := blockedToActivePhase(oldPhase)
	if err != nil {
		return "", err
	}

	state.ClearBlocker()

	if state.Retries != nil {
		switch oldPhase {
		case PhaseImplementationBlocked:
			state.Retries.Implementation = 0
		case PhaseCIBlocked:
			state.Retries.CIFix = 0
		}
	}

	state.Phase = activePhase
	return fmt.Sprintf("Reset from %s to %s, cleared blockers and reset retry counters", oldPhase, activePhase), nil
}

func handleActorSkip(state *ActorState, args string) (string, error) {
	if args == "" {
		return "", fmt.Errorf("actor-skip requires a phase name as argument")
	}

	targetPhase := Phase(strings.TrimSpace(args))

	// Validate phase name
	validPhases := []Phase{
		PhaseUnassigned, PhaseTriageReview, PhaseTriageBlocked,
		PhasePlanning, PhaseImplementing, PhaseTesting, PhaseImplementationBlocked,
		PhasePRCreating, PhaseCIWaiting, PhaseCIAnalyzing, PhaseCIBlocked,
		PhaseReviewWaiting, PhaseChangesRequested, PhaseAddressingFeedback, PhaseClarificationNeeded,
		PhaseMergeReady, PhaseMerged,
		PhaseBackportPlanning, PhaseBackportBotRequested, PhaseBackportImplementing,
		PhaseBackportCIWaiting, PhaseBackportReviewWaiting, PhaseBackportMerged,
		PhaseClosing, PhaseDone,
	}

	valid := false
	for _, p := range validPhases {
		if p == targetPhase {
			valid = true
			break
		}
	}

	if !valid {
		return "", fmt.Errorf("invalid phase name: %s", targetPhase)
	}

	oldPhase := state.Phase
	state.Phase = targetPhase

	// Clear blockers when skipping to a non-blocked phase
	if !strings.HasSuffix(string(targetPhase), "Blocked") {
		state.ClearBlocker()
	}

	return fmt.Sprintf("Skipped from %s to %s", oldPhase, targetPhase), nil
}

func handleActorContinue(state *ActorState) (string, error) {
	oldPhase := state.Phase
	activePhase, err := blockedToActivePhase(oldPhase)
	if err != nil {
		return "", err
	}

	state.ClearBlocker()
	state.Phase = activePhase

	return fmt.Sprintf("Cleared blocker, resuming from %s to %s", oldPhase, activePhase), nil
}

func blockedToActivePhase(phase Phase) (Phase, error) {
	switch phase {
	case PhaseTriageBlocked:
		return PhaseTriageReview, nil
	case PhaseImplementationBlocked:
		return PhaseImplementing, nil
	case PhaseCIBlocked:
		return PhaseCIWaiting, nil
	default:
		return "", fmt.Errorf("command is only valid in blocked phases (TriageBlocked, ImplementationBlocked, CIBlocked), current phase: %s", phase)
	}
}

func handleActorOverrideCI(state *ActorState) (string, error) {
	if state.Phase != PhaseCIBlocked {
		return "", fmt.Errorf("actor-override-ci is only valid in CIBlocked phase, current phase: %s", state.Phase)
	}

	pr := state.GetMainPR()
	if pr == nil {
		return "", fmt.Errorf("no active PR found")
	}

	// Mark CI as passing
	pr.CIStatus = "passing"

	// Clear blocker
	state.ClearBlocker()

	// Transition based on approval status
	var newPhase Phase
	if pr.HasApproval {
		newPhase = PhaseMergeReady
	} else {
		newPhase = PhaseReviewWaiting
	}

	state.Phase = newPhase

	return fmt.Sprintf("Overrode CI status, marked as passing, transitioned to %s", newPhase), nil
}

func handleActorAbandon(state *ActorState) (string, error) {
	oldPhase := state.Phase
	state.Phase = PhaseDone
	state.ClearBlocker()

	return fmt.Sprintf("Abandoned from %s, transitioned to Done", oldPhase), nil
}

func handleActorMerge(state *ActorState) (string, error) {
	if state.Phase != PhaseMergeReady {
		return "", fmt.Errorf("actor-merge is only valid in MergeReady phase, current phase: %s", state.Phase)
	}

	// For now, just signal merge intent by transitioning
	// Actual merge implementation will be in a future phase
	state.Phase = PhaseMerged

	return "Merge signaled, transitioned to Merged (actual merge is not yet implemented)", nil
}
