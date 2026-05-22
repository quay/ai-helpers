package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/quay/ai-helpers/substrate"
)

type Router struct {
	lifecycle  *ActorLifecycleManager
	atenetAddr string
	httpClient *http.Client
}

func (rt *Router) RouteGitHubEvent(ctx context.Context, actorID, eventType, action string, payload []byte) error {
	switch action {
	case "opened", "reopened":
		if err := rt.lifecycle.CreateActor(ctx, actorID); err != nil {
			return err
		}
		envelope := buildEnvelope("github", eventType, actorID, payload)
		resp, err := rt.forwardEnvelope(ctx, envelope)
		if err != nil {
			return err
		}
		if !resp.KeepAlive {
			if err := rt.lifecycle.SuspendActor(ctx, actorID); err != nil {
				slog.Error("failed to suspend actor after non-keepalive response", "actorID", actorID, "error", err)
			}
		}

	case "closed":
		if err := rt.lifecycle.SuspendActor(ctx, actorID); err != nil {
			return err
		}
		if err := rt.lifecycle.DeleteActor(ctx, actorID); err != nil {
			return err
		}

	default:
		envelope := buildEnvelope("github", eventType, actorID, payload)
		resp, err := rt.forwardEnvelope(ctx, envelope)
		if err != nil {
			return err
		}
		if !resp.KeepAlive {
			if err := rt.lifecycle.SuspendActor(ctx, actorID); err != nil {
				slog.Error("failed to suspend actor after non-keepalive response", "actorID", actorID, "error", err)
			}
		}
	}

	return nil
}

func (rt *Router) RouteJIRAEvent(ctx context.Context, actorID, eventType, action string, payload []byte) error {
	switch action {
	case "assignee_changed":
		if err := rt.lifecycle.CreateActor(ctx, actorID); err != nil {
			return err
		}
		envelope := buildEnvelope("jira", eventType, actorID, payload)
		resp, err := rt.forwardEnvelope(ctx, envelope)
		if err != nil {
			return err
		}
		if !resp.KeepAlive {
			if err := rt.lifecycle.SuspendActor(ctx, actorID); err != nil {
				slog.Error("failed to suspend actor after non-keepalive response", "actorID", actorID, "error", err)
			}
		}

	case "issue_deleted":
		if err := rt.lifecycle.SuspendActor(ctx, actorID); err != nil {
			return err
		}
		if err := rt.lifecycle.DeleteActor(ctx, actorID); err != nil {
			return err
		}

	default:
		envelope := buildEnvelope("jira", eventType, actorID, payload)
		resp, err := rt.forwardEnvelope(ctx, envelope)
		if err != nil {
			return err
		}
		if !resp.KeepAlive {
			if err := rt.lifecycle.SuspendActor(ctx, actorID); err != nil {
				slog.Error("failed to suspend actor after non-keepalive response", "actorID", actorID, "error", err)
			}
		}
	}

	return nil
}

func (rt *Router) forwardEnvelope(ctx context.Context, envelope substrate.EventEnvelope) (*substrate.EventResponse, error) {
	jsonBody, err := json.Marshal(envelope)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal envelope: %w", err)
	}

	url := fmt.Sprintf("http://%s/event", rt.atenetAddr)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Host = fmt.Sprintf("%s.actors.resources.substrate.ate.dev", envelope.ActorID)

	resp, err := rt.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request to actor: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("actor returned status %d: %s", resp.StatusCode, string(body))
	}

	var eventResp substrate.EventResponse
	if err := json.NewDecoder(resp.Body).Decode(&eventResp); err != nil {
		return nil, fmt.Errorf("failed to decode actor response: %w", err)
	}

	return &eventResp, nil
}

func buildEnvelope(source, eventType, actorID string, payload []byte) substrate.EventEnvelope {
	return substrate.EventEnvelope{
		EventID:   generateUUID(),
		Source:    source,
		EventType: eventType,
		Timestamp: time.Now(),
		ActorID:   actorID,
		Payload:   json.RawMessage(payload),
	}
}

func generateUUID() string {
	var uuid [16]byte
	rand.Read(uuid[:])
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", uuid[0:4], uuid[4:6], uuid[6:8], uuid[8:10], uuid[10:])
}
