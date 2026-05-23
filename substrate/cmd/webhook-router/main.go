package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/quay/ai-helpers/substrate/internal/envutil"
	"github.com/quay/ai-helpers/substrate/internal/webhook"
)

func main() {
	var (
		listenAddr   = flag.String("listen", envutil.Or("LISTEN_ADDR", ":8080"), "HTTP listen address")
		ateapiAddr   = flag.String("ateapi", envutil.Or("ATE_API_ENDPOINT", "api.ate-system.svc:443"), "ate-api-server gRPC endpoint")
		atenetAddr   = flag.String("atenet", envutil.Or("ATENET_ADDR", "atenet-router.ate-system.svc:80"), "atenet-router HTTP endpoint")
		templateNS   = flag.String("template-ns", envutil.Or("ACTOR_TEMPLATE_NAMESPACE", "ate-sdlc"), "ActorTemplate namespace")
		templateName = flag.String("template-name", envutil.Or("ACTOR_TEMPLATE_NAME", "sdlc"), "ActorTemplate name")
		githubSecret = flag.String("github-secret", envutil.Or("GITHUB_WEBHOOK_SECRET", ""), "GitHub webhook HMAC secret")
		jiraSecret   = flag.String("jira-secret", envutil.Or("JIRA_WEBHOOK_SECRET", ""), "JIRA webhook shared secret")
	)
	flag.Parse()

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	if *githubSecret == "" {
		slog.Warn("GITHUB_WEBHOOK_SECRET not set — GitHub webhook signature verification is disabled")
	}
	if *jiraSecret == "" {
		slog.Warn("JIRA_WEBHOOK_SECRET not set — JIRA webhook authentication is disabled")
	}

	lifecycle, err := webhook.NewActorLifecycleManager(*ateapiAddr, *templateNS, *templateName)
	if err != nil {
		slog.Error("failed to initialize actor lifecycle manager", "error", err)
		os.Exit(1)
	}
	defer lifecycle.Close()

	router := &webhook.Router{
		Lifecycle:  lifecycle,
		AtenetAddr: *atenetAddr,
		HTTPClient: &http.Client{Timeout: 30 * time.Second},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /webhook/github", webhook.MakeGitHubHandler(router, *githubSecret))
	mux.HandleFunc("POST /webhook/jira", webhook.MakeJIRAHandler(router, *jiraSecret))
	mux.HandleFunc("GET /healthz", webhook.HandleHealthz)

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
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("shutdown error", "error", err)
		}
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
