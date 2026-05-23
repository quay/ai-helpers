package actor

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"runtime/debug"
	"sync"

	"github.com/quay/ai-helpers/substrate/internal/event"
)

type Handler struct {
	state     *ActorState
	mu        sync.RWMutex
	statePath string

	github GitHubAPI
	jira   JIRAAPI
	claude ClaudeAPI
	ate    ATEAPI
	git    GitOperations
}

func NewHandler(statePath string, gh GitHubAPI, jira JIRAAPI, claude ClaudeAPI, ate ATEAPI, git GitOperations) (*Handler, error) {
	state, err := LoadState(statePath)
	if err != nil {
		slog.Warn("failed to load state, using empty state",
			slog.String("path", statePath),
			slog.String("error", err.Error()))
		state = newEmptyState()
	}

	return &Handler{
		state:     state,
		statePath: statePath,
		github:    gh,
		jira:      jira,
		claude:    claude,
		ate:       ate,
		git:       git,
	}, nil
}

func (h *Handler) HandleEvent(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		slog.Error("failed to read request body", slog.String("error", err.Error()))
		http.Error(w, "failed to read body", http.StatusBadRequest)
		return
	}

	var envelope event.Envelope
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

	h.mu.Lock()

	if h.state.IsEventProcessed(envelope.EventID) {
		h.mu.Unlock()
		slog.Info("duplicate event, skipping", slog.String("eventID", envelope.EventID))
		respondJSON(w, event.Response{KeepAlive: false, Message: "duplicate"})
		return
	}

	if h.state.ActorID == "" {
		h.state.ActorID = envelope.ActorID
	}

	var decision string
	switch envelope.Source {
	case "github":
		decision, err = ProcessGitHubEvent(h, h.state, envelope.EventType, envelope.Payload)
	case "jira":
		decision, err = ProcessJIRAEvent(h, h.state, envelope.Payload)
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

	h.state.AddEvent(envelope.EventID, envelope.Source, envelope.EventType, decision, result)

	if h.state.Phase == PhaseBackportPlanning {
		planBackports(h, h.state)
	}

	if err := h.state.Save(h.statePath); err != nil {
		h.mu.Unlock()
		slog.Error("failed to save state", slog.String("error", err.Error()))
		http.Error(w, "failed to save state", http.StatusInternalServerError)
		return
	}

	if asyncWork := h.selectAsyncWork(h.state.Phase); asyncWork != nil {
		actorID := h.state.ActorID
		ttl := asyncWork.ttl
		h.mu.Unlock()

		respondJSON(w, event.Response{KeepAlive: true, TTL: ttl, Message: decision})

		go h.runAsyncWork(asyncWork, actorID)
		return
	}

	h.mu.Unlock()
	respondJSON(w, event.Response{KeepAlive: false, Message: decision})
}

func (h *Handler) runAsyncWork(work *asyncWorkItem, actorID string) {
	defer func() {
		if r := recover(); r != nil {
			slog.Error("async work panicked",
				slog.String("actorID", actorID),
				slog.Any("panic", r),
				slog.String("stack", string(debug.Stack())))

			h.mu.Lock()
			h.state.SetBlocker("async_work_panic", []string{fmt.Sprintf("%v", r)})
			if err := h.state.Save(h.statePath); err != nil {
				slog.Error("failed to save state after panic", slog.String("error", err.Error()))
			}
			h.mu.Unlock()
		}
	}()

	work.run(h, h.state)

	h.mu.Lock()
	if err := h.state.Save(h.statePath); err != nil {
		slog.Error("failed to save state after async work", slog.String("error", err.Error()))
	}
	h.mu.Unlock()

	if h.ate != nil {
		h.ate.SuspendSelf(actorID)
	}
}

type asyncWorkItem struct {
	run func(h *Handler, state *ActorState)
	ttl int
}

func (h *Handler) selectAsyncWork(phase Phase) *asyncWorkItem {
	switch {
	case shouldStartChain(phase):
		return &asyncWorkItem{run: runImplementationChain, ttl: 900}
	case shouldStartCIAnalysis(phase) && h.claude != nil:
		return &asyncWorkItem{run: runCIAnalysisChain, ttl: 300}
	case shouldStartReviewHandling(phase) && h.claude != nil:
		return &asyncWorkItem{run: runReviewFeedbackChain, ttl: 300}
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

func (h *Handler) HandleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
		slog.Error("failed to encode health response", slog.String("error", err.Error()))
	}
}

func (h *Handler) HandleStatus(w http.ResponseWriter, r *http.Request) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(h.state); err != nil {
		slog.Error("failed to encode state", slog.String("error", err.Error()))
		http.Error(w, "failed to encode state", http.StatusInternalServerError)
		return
	}
}
