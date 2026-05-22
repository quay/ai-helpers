package main

import (
	"encoding/json"
	"fmt"
)

func ProcessJIRAEvent(state *ActorState, payload []byte) (decision string, err error) {
	var event struct {
		WebhookEvent string `json:"webhookEvent"`
		Issue        struct {
			Key string `json:"key"`
		} `json:"issue"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling JIRA event: %w", err)
	}

	state.Ticket = event.Issue.Key

	return fmt.Sprintf("logged JIRA event: %s", event.WebhookEvent), nil
}
