package main

import (
	"encoding/base64"
	"flag"
	"log/slog"
	"net/http"
	"os"

	"github.com/quay/ai-helpers/substrate/internal/actor"
	"github.com/quay/ai-helpers/substrate/internal/envutil"
)

func main() {
	listenAddr := flag.String("listen", envutil.Or("LISTEN_ADDR", ":80"), "HTTP listen address")
	statePathFlag := flag.String("state-path", envutil.Or("STATE_PATH", "/tmp/actor-state.json"), "path to state file")
	flag.Parse()

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, nil)))

	setupGCPCredentials()

	var gh actor.GitHubAPI
	if ghImpl := actor.NewGitHubClient(); ghImpl != nil {
		gh = ghImpl
		slog.Info("GitHub client initialized")
	}

	var jira actor.JIRAAPI
	if jiraImpl := actor.NewJIRAClient(); jiraImpl != nil {
		jira = jiraImpl
		slog.Info("JIRA client initialized")
	}

	var ate actor.ATEAPI
	if ateImpl := actor.NewAteClient(); ateImpl != nil {
		ate = ateImpl
		slog.Info("ate-api client initialized")
		defer ateImpl.Close()
	}

	claude := actor.ClaudeAPI(actor.NewClaudeCodeClient())
	slog.Info("claude code client initialized")

	git := actor.GitOperations(actor.NewGitOpsClient(actor.RepoDir()))

	handler, err := actor.NewHandler(*statePathFlag, gh, jira, claude, ate, git)
	if err != nil {
		slog.Error("failed to initialize handler", slog.String("error", err.Error()))
		os.Exit(1)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /event", handler.HandleEvent)
	mux.HandleFunc("GET /health", handler.HandleHealth)
	mux.HandleFunc("GET /status", handler.HandleStatus)
	mux.HandleFunc("GET /debug/claude-log", func(w http.ResponseWriter, r *http.Request) {
		data, err := os.ReadFile("/tmp/claude-debug.log")
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		w.Write(data)
	})

	slog.Info("starting sdlc actor", slog.String("listen", *listenAddr), slog.String("statePath", *statePathFlag))
	if err := http.ListenAndServe(*listenAddr, mux); err != nil {
		slog.Error("server failed", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

func setupGCPCredentials() {
	keyB64 := os.Getenv("GCP_SA_KEY_B64")
	if keyB64 == "" {
		return
	}
	key, err := base64.StdEncoding.DecodeString(keyB64)
	if err != nil {
		slog.Error("failed to decode GCP_SA_KEY_B64", slog.String("error", err.Error()))
		return
	}
	os.MkdirAll("/tmp/home", 0o755)
	path := "/tmp/home/gcp-sa-key.json"
	if err := os.WriteFile(path, key, 0o600); err != nil {
		slog.Error("failed to write GCP credentials", slog.String("error", err.Error()))
		return
	}
	os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", path)
	slog.Info("GCP credentials configured")
}

