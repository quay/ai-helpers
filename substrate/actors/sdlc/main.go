package main

import (
	"flag"
	"log/slog"
	"net/http"
	"os"
)

func main() {
	listenAddr := flag.String("listen", envOr("LISTEN_ADDR", ":80"), "HTTP listen address")
	statePathFlag := flag.String("state-path", envOr("STATE_PATH", "/state/actor-state.json"), "path to state file")
	flag.Parse()

	statePath = *statePathFlag

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	state, err := LoadState(statePath)
	if err != nil {
		slog.Warn("failed to load state, using empty state",
			slog.String("path", statePath),
			slog.String("error", err.Error()))
		state = &ActorState{Events: []EventRecord{}}
	}
	actorState = state

	mux := http.NewServeMux()
	mux.HandleFunc("POST /event", handleEvent)
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /status", handleStatus)

	slog.Info("starting sdlc actor", slog.String("listen", *listenAddr), slog.String("statePath", statePath))
	if err := http.ListenAndServe(*listenAddr, mux); err != nil {
		slog.Error("server failed", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
