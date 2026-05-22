package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	var (
		listenAddr   = flag.String("listen", envOr("LISTEN_ADDR", ":8080"), "HTTP listen address")
		ateapiAddr   = flag.String("ateapi", envOr("ATE_API_ENDPOINT", "api.ate-system.svc:443"), "ate-api-server gRPC endpoint")
		atenetAddr   = flag.String("atenet", envOr("ATENET_ADDR", "atenet-router.ate-system.svc:80"), "atenet-router HTTP endpoint")
		templateNS   = flag.String("template-ns", envOr("ACTOR_TEMPLATE_NAMESPACE", "ate-sdlc"), "ActorTemplate namespace")
		templateName = flag.String("template-name", envOr("ACTOR_TEMPLATE_NAME", "sdlc"), "ActorTemplate name")
		githubSecret = flag.String("github-secret", envOr("GITHUB_WEBHOOK_SECRET", ""), "GitHub webhook HMAC secret")
	)
	flag.Parse()

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	lifecycle, err := NewActorLifecycleManager(*ateapiAddr, *templateNS, *templateName)
	if err != nil {
		slog.Error("failed to initialize actor lifecycle manager", "error", err)
		os.Exit(1)
	}
	defer lifecycle.Close()

	router := &Router{
		lifecycle:  lifecycle,
		atenetAddr: *atenetAddr,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /webhook/github", makeGitHubHandler(router, *githubSecret))
	mux.HandleFunc("POST /webhook/jira", makeJIRAHandler(router))
	mux.HandleFunc("GET /healthz", handleHealthz)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	srv := &http.Server{
		Addr:              *listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.Shutdown(shutdownCtx)
	}()

	slog.Info("starting webhook-router",
		"listen", *listenAddr,
		"ateapi", *ateapiAddr,
		"atenet", *atenetAddr,
		"template", fmt.Sprintf("%s/%s", *templateNS, *templateName),
	)

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}
}

func makeGitHubHandler(router *Router, secret string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			slog.Error("failed to read request body", "error", err)
			http.Error(w, "failed to read body", http.StatusBadRequest)
			return
		}

		if secret != "" {
			signature := r.Header.Get("X-Hub-Signature-256")
			if err := verifyGitHubSignature(body, signature, secret); err != nil {
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

		actorID, action, err := parseGitHubEvent(eventType, body)
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
		w.Write([]byte(`{"ok":true}`))
	}
}

func makeJIRAHandler(router *Router) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			slog.Error("failed to read request body", "error", err)
			http.Error(w, "failed to read body", http.StatusBadRequest)
			return
		}

		actorID, eventType, action, err := parseJIRAEvent(body)
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
		w.Write([]byte(`{"ok":true}`))
	}
}

func handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func envOr(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}
