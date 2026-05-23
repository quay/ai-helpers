package event

import (
	"encoding/json"
	"time"
)

type Envelope struct {
	EventID   string          `json:"eventID"`
	Source    string          `json:"source"`
	EventType string          `json:"eventType"`
	Timestamp time.Time       `json:"timestamp"`
	ActorID   string          `json:"actorID"`
	Payload   json.RawMessage `json:"payload"`
}

type Response struct {
	KeepAlive bool   `json:"keepAlive"`
	Message   string `json:"message"`
	TTL       int    `json:"ttl,omitempty"`
}
