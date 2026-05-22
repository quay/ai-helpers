package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type ActorState struct {
	ActorID string        `json:"actorID"`
	Ticket  string        `json:"ticket,omitempty"`
	Phase   string        `json:"phase"`
	PR      *PRState      `json:"pr,omitempty"`
	Events  []EventRecord `json:"events"`
}

type PRState struct {
	Repo        string `json:"repo"`
	Number      int    `json:"number"`
	HeadSHA     string `json:"headSHA"`
	CIStatus    string `json:"ciStatus"`
	HasApproval bool   `json:"hasApproval"`
	ThreadsOpen int    `json:"threadsOpen"`
	Conclusion  string `json:"conclusion"`
}

type EventRecord struct {
	Timestamp time.Time `json:"timestamp"`
	Source    string    `json:"source"`
	Type      string    `json:"type"`
	Decision  string    `json:"decision"`
	Result    string    `json:"result"`
}

func LoadState(path string) (*ActorState, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &ActorState{Events: []EventRecord{}}, nil
		}
		return nil, fmt.Errorf("while reading state file: %w", err)
	}

	var state ActorState
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("while unmarshaling state: %w", err)
	}

	if state.Events == nil {
		state.Events = []EventRecord{}
	}

	return &state, nil
}

func (s *ActorState) Save(path string) error {
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return fmt.Errorf("while marshaling state: %w", err)
	}

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("while creating state directory: %w", err)
	}
	tmpFile, err := os.CreateTemp(dir, "actor-state-*.json.tmp")
	if err != nil {
		return fmt.Errorf("while creating temp file: %w", err)
	}
	tmpPath := tmpFile.Name()

	if _, err := tmpFile.Write(data); err != nil {
		tmpFile.Close()
		os.Remove(tmpPath)
		return fmt.Errorf("while writing temp file: %w", err)
	}

	if err := tmpFile.Close(); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("while closing temp file: %w", err)
	}

	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("while renaming temp file: %w", err)
	}

	return nil
}

func (s *ActorState) AddEvent(source, eventType, decision, result string) {
	s.Events = append(s.Events, EventRecord{
		Timestamp: time.Now(),
		Source:    source,
		Type:      eventType,
		Decision:  decision,
		Result:    result,
	})
}
