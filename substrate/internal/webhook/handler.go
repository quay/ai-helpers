package webhook

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
)

func MakeGitHubHandler(router *Router, secret string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			slog.Error("failed to read request body", "error", err)
			http.Error(w, "failed to read body", http.StatusBadRequest)
			return
		}

		if secret != "" {
			signature := r.Header.Get("X-Hub-Signature-256")
			if err := VerifyGitHubSignature(body, signature, secret); err != nil {
				slog.Warn("signature verification failed", "error", err, "remote_addr", r.RemoteAddr)
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
		}

		eventType := r.Header.Get("X-GitHub-Event")
		if eventType == "" {
			slog.Error("missing X-GitHub-Event header")
			http.Error(w, "missing X-GitHub-Event header", http.StatusBadRequest)
			return
		}

		actorID, action, err := ParseGitHubEvent(eventType, body)
		if err != nil {
			slog.Error("failed to parse GitHub event",
				"error", err,
				"eventType", eventType,
			)
			http.Error(w, fmt.Sprintf("failed to parse event: %v", err), http.StatusBadRequest)
			return
		}

		slog.Info("received GitHub webhook",
			"eventType", eventType,
			"action", action,
			"actorID", actorID,
		)

		if err := router.RouteGitHubEvent(r.Context(), actorID, eventType, action, body); err != nil {
			slog.Error("failed to route GitHub event",
				"error", err,
				"actorID", actorID,
				"eventType", eventType,
				"action", action,
			)
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}
}

func MakeJIRAHandler(router *Router, secret string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			slog.Error("failed to read request body", "error", err)
			http.Error(w, "failed to read body", http.StatusBadRequest)
			return
		}

		if secret != "" {
			provided := r.Header.Get("X-Webhook-Secret")
			if provided != secret {
				slog.Warn("JIRA webhook secret mismatch", "remote_addr", r.RemoteAddr)
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
		}

		actorID, eventType, action, err := ParseJIRAEvent(body)
		if err != nil {
			slog.Error("failed to parse JIRA event", "error", err)
			http.Error(w, fmt.Sprintf("failed to parse event: %v", err), http.StatusBadRequest)
			return
		}

		slog.Info("received JIRA webhook",
			"eventType", eventType,
			"action", action,
			"actorID", actorID,
		)

		if err := router.RouteJIRAEvent(r.Context(), actorID, eventType, action, body); err != nil {
			slog.Error("failed to route JIRA event",
				"error", err,
				"actorID", actorID,
				"eventType", eventType,
				"action", action,
			)
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}
}

func HandleHealthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}
