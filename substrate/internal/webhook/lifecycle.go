package webhook

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/agent-substrate/substrate/proto/ateapipb"
	"github.com/quay/ai-helpers/substrate/internal/grpcutil"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type ActorLifecycleManager struct {
	client       ateapipb.ControlClient
	conn         *grpc.ClientConn
	templateNS   string
	templateName string
}

func NewActorLifecycleManager(endpoint, templateNS, templateName string) (*ActorLifecycleManager, error) {
	creds := grpcutil.TLSCredentials()

	conn, err := grpc.NewClient(endpoint, grpc.WithTransportCredentials(creds))
	if err != nil {
		return nil, fmt.Errorf("failed to dial ate-api at %s: %w", endpoint, err)
	}

	return &ActorLifecycleManager{
		client:       ateapipb.NewControlClient(conn),
		conn:         conn,
		templateNS:   templateNS,
		templateName: templateName,
	}, nil
}

func (m *ActorLifecycleManager) CreateActor(ctx context.Context, actorID string) error {
	_, err := m.client.CreateActor(ctx, &ateapipb.CreateActorRequest{
		ActorId:                actorID,
		ActorTemplateNamespace: m.templateNS,
		ActorTemplateName:      m.templateName,
	})
	if err != nil {
		if status.Code(err) == codes.AlreadyExists {
			slog.Warn("actor already exists", "actorID", actorID)
			return nil
		}
		return fmt.Errorf("failed to create actor %s: %w", actorID, err)
	}

	slog.Info("created actor", "actorID", actorID)
	return nil
}

func (m *ActorLifecycleManager) SuspendActor(ctx context.Context, actorID string) error {
	_, err := m.client.SuspendActor(ctx, &ateapipb.SuspendActorRequest{
		ActorId: actorID,
	})
	if err != nil {
		if status.Code(err) == codes.NotFound {
			slog.Warn("actor not found for suspend", "actorID", actorID)
			return nil
		}
		return fmt.Errorf("failed to suspend actor %s: %w", actorID, err)
	}

	slog.Info("suspended actor", "actorID", actorID)
	return nil
}

func (m *ActorLifecycleManager) DeleteActor(ctx context.Context, actorID string) error {
	_, err := m.client.DeleteActor(ctx, &ateapipb.DeleteActorRequest{
		ActorId: actorID,
	})
	if err != nil {
		code := status.Code(err)
		if code == codes.NotFound {
			slog.Warn("actor not found for delete", "actorID", actorID)
			return nil
		}
		if code == codes.FailedPrecondition {
			return fmt.Errorf("actor %s must be suspended before deletion: %w", actorID, err)
		}
		return fmt.Errorf("failed to delete actor %s: %w", actorID, err)
	}

	slog.Info("deleted actor", "actorID", actorID)
	return nil
}

func (m *ActorLifecycleManager) GetActor(ctx context.Context, actorID string) (*ateapipb.Actor, error) {
	resp, err := m.client.GetActor(ctx, &ateapipb.GetActorRequest{
		ActorId: actorID,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get actor %s: %w", actorID, err)
	}
	return resp.Actor, nil
}

func (m *ActorLifecycleManager) Close() {
	if m.conn != nil {
		m.conn.Close()
	}
}
