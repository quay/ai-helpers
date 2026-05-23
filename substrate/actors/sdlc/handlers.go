package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"sync"

	"github.com/quay/ai-helpers/substrate"
)

var (
	actorState *ActorState
	stateMutex sync.Mutex
	statePath  = "/state/actor-state.json"
	jiraClient *JIRAClient
)

func handleEvent(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		slog.Error("failed to read request body", slog.String("error", err.Error()))
		http.Error(w, "failed to read body", http.StatusBadRequest)
		return
	}

	var envelope substrate.EventEnvelope
	if err := json.Unmarshal(body, &envelope); err != nil {
		slog.Error("failed to unmarshal envelope", slog.String("error", err.Error()))
		http.Error(w, "invalid envelope", http.StatusBadRequest)
		return
	}

	slog.Info("received event",
		slog.String("eventID", envelope.EventID),
		slog.String("source", envelope.Source),
		slog.String("eventType", envelope.EventType),
		slog.String("actorID", envelope.ActorID))

	stateMutex.Lock()

	if actorState.IsEventProcessed(envelope.EventID) {
		stateMutex.Unlock()
		slog.Info("duplicate event, skipping", slog.String("eventID", envelope.EventID))
		respondJSON(w, substrate.EventResponse{KeepAlive: false, Message: "duplicate"})
		return
	}

	if actorState.ActorID == "" {
		actorState.ActorID = envelope.ActorID
	}

	var decision string
	switch envelope.Source {
	case "github":
		decision, err = ProcessGitHubEvent(actorState, envelope.EventType, envelope.Payload)
	case "jira":
		decision, err = ProcessJIRAEvent(actorState, envelope.Payload)
	default:
		decision = "unknown source"
		err = fmt.Errorf("unknown event source: %s", envelope.Source)
	}

	result := "ok"
	if err != nil {
		slog.Error("failed to process event",
			slog.String("source", envelope.Source),
			slog.String("error", err.Error()))
		result = err.Error()
		decision = "error"
	}

	actorState.AddEvent(envelope.EventID, envelope.Source, envelope.EventType, decision, result)

	if err := actorState.Save(statePath); err != nil {
		stateMutex.Unlock()
		slog.Error("failed to save state", slog.String("error", err.Error()))
		http.Error(w, "failed to save state", http.StatusInternalServerError)
		return
	}

	if asyncWork := selectAsyncWork(actorState.Phase); asyncWork != nil && claudeClient != nil {
		actorID := actorState.ActorID
		ttl := asyncWork.ttl
		stateMutex.Unlock()

		respondJSON(w, substrate.EventResponse{KeepAlive: true, TTL: ttl, Message: decision})

		go func() {
			stateMutex.Lock()
			defer stateMutex.Unlock()

			asyncWork.run(actorState)

			if err := actorState.Save(statePath); err != nil {
				slog.Error("failed to save state after async work", slog.String("error", err.Error()))
			}

			ateClient.SuspendSelf(actorID)
		}()
		return
	}

	stateMutex.Unlock()
	respondJSON(w, substrate.EventResponse{KeepAlive: false, Message: decision})
}

type asyncWorkItem struct {
	run func(state *ActorState)
	ttl int
}

func selectAsyncWork(phase Phase) *asyncWorkItem {
	switch {
	case shouldStartChain(phase):
		return &asyncWorkItem{run: runImplementationChain, ttl: 900}
	case shouldStartCIAnalysis(phase):
		return &asyncWorkItem{run: runCIAnalysisChain, ttl: 300}
	default:
		return nil
	}
}

func respondJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("failed to encode response", slog.String("error", err.Error()))
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	stateMutex.Lock()
	defer stateMutex.Unlock()

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(actorState); err != nil {
		slog.Error("failed to encode state", slog.String("error", err.Error()))
		http.Error(w, "failed to encode state", http.StatusInternalServerError)
		return
	}
}
