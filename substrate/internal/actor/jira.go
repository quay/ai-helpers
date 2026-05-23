package actor

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"time"
)

func ProcessJIRAEvent(h *Handler, state *ActorState, payload []byte) (string, error) {
	var event jiraWebhookEvent
	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling JIRA event: %w", err)
	}

	state.Ticket = event.Issue.Key
	populateJIRAContext(state, &event)

	action := detectJIRAAction(&event)

	switch action {
	case "assignee_changed":
		return handleAssigneeChange(h, state, &event)
	case "description_updated":
		return handleFieldUpdate(h, state, &event)
	default:
		return fmt.Sprintf("logged JIRA event: %s (action: %s)", event.WebhookEvent, action), nil
	}
}

type jiraWebhookEvent struct {
	WebhookEvent string `json:"webhookEvent"`
	Issue        struct {
		Key    string `json:"key"`
		Fields struct {
			IssueType struct {
				Name string `json:"name"`
			} `json:"issuetype"`
			Summary     string `json:"summary"`
			Description string `json:"description"`
			Status      struct {
				Name string `json:"name"`
			} `json:"status"`
			Priority struct {
				Name string `json:"name"`
			} `json:"priority"`
			Assignee struct {
				DisplayName string `json:"displayName"`
			} `json:"assignee"`

			CustomEmbargoStatus  string `json:"customfield_10860"`
			CustomTargetVersions []struct {
				Name string `json:"name"`
			} `json:"customfield_10855"`
		} `json:"fields"`
	} `json:"issue"`
	Changelog struct {
		Items []struct {
			Field    string `json:"field"`
			ToString string `json:"toString"`
		} `json:"items"`
	} `json:"changelog"`
}

func detectJIRAAction(event *jiraWebhookEvent) string {
	if strings.Contains(event.WebhookEvent, "deleted") {
		return "issue_deleted"
	}
	for _, item := range event.Changelog.Items {
		switch item.Field {
		case "assignee":
			return "assignee_changed"
		case "description":
			return "description_updated"
		case "status":
			return "status_changed"
		}
	}
	return "updated"
}

func populateJIRAContext(state *ActorState, event *jiraWebhookEvent) {
	if state.JIRA == nil {
		state.JIRA = &JIRAContext{}
	}

	f := &event.Issue.Fields
	state.JIRA.Key = event.Issue.Key
	state.JIRA.Type = f.IssueType.Name
	state.JIRA.Summary = f.Summary
	state.JIRA.Description = f.Description
	state.JIRA.Status = f.Status.Name
	state.JIRA.Priority = f.Priority.Name
	state.JIRA.Assignee = f.Assignee.DisplayName
	state.JIRA.EmbargoStatus = f.CustomEmbargoStatus
	state.JIRA.UpdatedAt = time.Now()

	if len(f.CustomTargetVersions) > 0 {
		versions := make([]string, 0, len(f.CustomTargetVersions))
		for _, v := range f.CustomTargetVersions {
			versions = append(versions, v.Name)
		}
		state.JIRA.TargetVersions = versions
	}
}

func handleAssigneeChange(h *Handler, state *ActorState, event *jiraWebhookEvent) (string, error) {
	assignee := event.Issue.Fields.Assignee.DisplayName
	if assignee == "" {
		state.Phase = PhaseUnassigned
		state.ClearBlocker()
		return "unassigned", nil
	}

	state.Phase = PhaseTriageReview
	return applyTriageResult(h, state)
}

func handleFieldUpdate(h *Handler, state *ActorState, event *jiraWebhookEvent) (string, error) {
	if state.Phase != PhaseTriageBlocked {
		return fmt.Sprintf("logged field update (phase: %s)", state.Phase), nil
	}

	return applyTriageResult(h, state)
}

func applyTriageResult(h *Handler, state *ActorState) (string, error) {
	result := triageTicket(state)

	if result.Refuse {
		state.Phase = PhaseDone
		slog.Warn("refusing embargoed ticket", slog.String("ticket", state.Ticket))
		return "refused: embargoed", nil
	}

	if result.Ready {
		state.Phase = PhasePlanning
		state.ClearBlocker()
		return "triage passed, ready for planning", nil
	}

	state.Phase = PhaseTriageBlocked
	state.SetBlocker("triage_failed", result.Blockers)

	if h.jira != nil {
		comment := fmt.Sprintf("SDLC Actor: This ticket is missing required information and cannot be worked on yet.\n\nBlockers:\n- %s\n\nPlease update the ticket to resolve these issues.",
			strings.Join(result.Blockers, "\n- "))
		if err := h.jira.AddComment(state.Ticket, comment); err != nil {
			slog.Error("failed to post triage comment to JIRA",
				slog.String("ticket", state.Ticket),
				slog.String("error", err.Error()))
		}
	}

	return fmt.Sprintf("triage blocked: %s", strings.Join(result.Blockers, ", ")), nil
}
