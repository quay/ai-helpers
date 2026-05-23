package webhook

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"slices"
	"time"

	"github.com/quay/ai-helpers/substrate/internal/event"
)

type Router struct {
	Lifecycle  *ActorLifecycleManager
	AtenetAddr string
	HTTPClient *http.Client
}

func (rt *Router) RouteGitHubEvent(ctx context.Context, actorID, eventType, action string, payload []byte) error {
	createActions := []string{"opened", "reopened"}
	deleteActions := []string{"closed"}
	return rt.routeEvent(ctx, "github", actorID, eventType, action, payload, createActions, deleteActions)
}

func (rt *Router) RouteJIRAEvent(ctx context.Context, actorID, eventType, action string, payload []byte) error {
	createActions := []string{"assignee_changed"}
	deleteActions := []string{"issue_deleted"}
	return rt.routeEvent(ctx, "jira", actorID, eventType, action, payload, createActions, deleteActions)
}

func (rt *Router) routeEvent(ctx context.Context, source, actorID, eventType, action string, payload []byte, createActions, deleteActions []string) error {
	if slices.Contains(deleteActions, action) {
		if err := rt.Lifecycle.SuspendActor(ctx, actorID); err != nil {
			return err
		}
		return rt.Lifecycle.DeleteActor(ctx, actorID)
	}

	if slices.Contains(createActions, action) {
		if err := rt.Lifecycle.CreateActor(ctx, actorID); err != nil {
			return err
		}
	}

	envelope := buildEnvelope(source, eventType, actorID, payload)
	resp, err := rt.forwardEnvelope(ctx, envelope)
	if err != nil {
		return err
	}
	if !resp.KeepAlive {
		if err := rt.Lifecycle.SuspendActor(ctx, actorID); err != nil {
			slog.Error("failed to suspend actor after non-keepalive response", "actorID", actorID, "error", err)
		}
	}

	return nil
}

func (rt *Router) forwardEnvelope(ctx context.Context, envelope event.Envelope) (*event.Response, error) {
	jsonBody, err := json.Marshal(envelope)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal envelope: %w", err)
	}

	url := fmt.Sprintf("http://%s/event", rt.AtenetAddr)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Host = fmt.Sprintf("%s.actors.resources.substrate.ate.dev", envelope.ActorID)

	resp, err := rt.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request to actor: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("actor returned status %d: %s", resp.StatusCode, string(body))
	}

	var eventResp event.Response
	if err := json.NewDecoder(resp.Body).Decode(&eventResp); err != nil {
		return nil, fmt.Errorf("failed to decode actor response: %w", err)
	}

	return &eventResp, nil
}

func buildEnvelope(source, eventType, actorID string, payload []byte) event.Envelope {
	return event.Envelope{
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
	if _, err := rand.Read(uuid[:]); err != nil {
		slog.Error("failed to generate UUID", "error", err)
	}
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", uuid[0:4], uuid[4:6], uuid[6:8], uuid[8:10], uuid[10:])
}
