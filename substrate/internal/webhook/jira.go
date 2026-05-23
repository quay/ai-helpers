package webhook

import (
	"encoding/json"
	"fmt"
	"strings"
)

func ParseJIRAEvent(payload []byte) (actorID string, eventType string, action string, err error) {
	var ev struct {
		WebhookEvent string `json:"webhookEvent"`
		Issue        struct {
			Key string `json:"key"`
		} `json:"issue"`
		Changelog *struct {
			Items []struct {
				Field string `json:"field"`
			} `json:"items"`
		} `json:"changelog"`
	}

	if err := json.Unmarshal(payload, &ev); err != nil {
		return "", "", "", fmt.Errorf("failed to parse JIRA event: %w", err)
	}

	if ev.Issue.Key == "" {
		return "", "", "", fmt.Errorf("missing issue.key in JIRA event")
	}

	eventType = ev.WebhookEvent
	actorID = strings.ToLower(ev.Issue.Key)

	if strings.Contains(eventType, "deleted") {
		action = "issue_deleted"
		return actorID, eventType, action, nil
	}

	if ev.Changelog != nil {
		for _, item := range ev.Changelog.Items {
			if item.Field == "assignee" {
				action = "assignee_changed"
				return actorID, eventType, action, nil
			}
			if item.Field == "status" {
				action = "status_changed"
				return actorID, eventType, action, nil
			}
		}
	}

	action = "updated"
	return actorID, eventType, action, nil
}
