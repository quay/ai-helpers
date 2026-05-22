package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

func parseJIRAEvent(payload []byte) (actorID string, eventType string, action string, err error) {
	var event struct {
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

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", "", "", fmt.Errorf("failed to parse JIRA event: %w", err)
	}

	if event.Issue.Key == "" {
		return "", "", "", fmt.Errorf("missing issue.key in JIRA event")
	}

	eventType = event.WebhookEvent
	actorID = strings.ToLower(event.Issue.Key)

	if strings.Contains(eventType, "deleted") {
		action = "issue_deleted"
		return actorID, eventType, action, nil
	}

	if event.Changelog != nil {
		for _, item := range event.Changelog.Items {
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
