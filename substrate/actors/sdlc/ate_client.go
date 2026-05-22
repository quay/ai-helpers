package main

import (
	"context"
	"crypto/tls"
	"log/slog"
	"os"

	"github.com/agent-substrate/substrate/proto/ateapipb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

var ateClient *AteClient

type AteClient struct {
	client ateapipb.ControlClient
	conn   *grpc.ClientConn
}

func NewAteClient() *AteClient {
	addr := os.Getenv("ATE_API_ADDR")
	if addr == "" {
		addr = "api.ate-system.svc.cluster.local:443"
	}

	creds := credentials.NewTLS(&tls.Config{InsecureSkipVerify: true})
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(creds))
	if err != nil {
		slog.Error("failed to connect to ate-api", slog.String("addr", addr), slog.String("error", err.Error()))
		return nil
	}

	return &AteClient{
		client: ateapipb.NewControlClient(conn),
		conn:   conn,
	}
}

func (c *AteClient) SuspendSelf(actorID string) {
	if c == nil {
		return
	}
	slog.Info("requesting self-suspension", slog.String("actorID", actorID))
	_, err := c.client.SuspendActor(context.Background(), &ateapipb.SuspendActorRequest{
		ActorId: actorID,
	})
	if err != nil {
		slog.Error("failed to self-suspend", slog.String("actorID", actorID), slog.String("error", err.Error()))
	}
}

func (c *AteClient) Close() {
	if c != nil && c.conn != nil {
		c.conn.Close()
	}
}
