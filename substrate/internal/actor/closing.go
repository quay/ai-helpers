package actor

import (
	"fmt"
	"log/slog"
	"strings"
)

func closeTicket(h *Handler, state *ActorState) {
	if h.jira != nil && state.JIRA != nil {
		summary := buildClosingSummary(state)
		if err := h.jira.AddComment(state.JIRA.Key, summary); err != nil {
			slog.Error("failed to post closing comment to JIRA",
				slog.String("ticket", state.Ticket),
				slog.String("error", err.Error()))
		}
	}

	state.Phase = PhaseDone
	slog.Info("ticket closed", slog.String("ticket", state.Ticket))
}

func buildClosingSummary(state *ActorState) string {
	var sb strings.Builder
	sb.WriteString("SDLC Actor: Ticket work completed.\n\n")
	sb.WriteString("Pull Requests:\n")

	for branch, pr := range state.PRs {
		if pr.URL != "" {
			sb.WriteString(fmt.Sprintf("- %s: %s (%s)\n", branch, pr.URL, pr.Conclusion))
		} else if pr.Number > 0 {
			sb.WriteString(fmt.Sprintf("- %s: #%d (%s)\n", branch, pr.Number, pr.Conclusion))
		}
	}

	return sb.String()
}
