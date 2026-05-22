package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type Phase string

const (
	PhaseUnassigned    Phase = "Unassigned"
	PhaseTriageReview  Phase = "TriageReview"
	PhaseTriageBlocked Phase = "TriageBlocked"

	PhasePlanning              Phase = "Planning"
	PhaseImplementing          Phase = "Implementing"
	PhaseTesting               Phase = "Testing"
	PhaseImplementationBlocked Phase = "ImplementationBlocked"

	PhasePRCreating Phase = "PRCreating"
	PhaseCIWaiting  Phase = "CIWaiting"

	PhaseCIAnalyzing Phase = "CIAnalyzing"
	PhaseCIBlocked   Phase = "CIBlocked"

	PhaseReviewWaiting       Phase = "ReviewWaiting"
	PhaseChangesRequested    Phase = "ChangesRequested"
	PhaseAddressingFeedback  Phase = "AddressingFeedback"
	PhaseClarificationNeeded Phase = "ClarificationNeeded"

	PhaseMergeReady Phase = "MergeReady"
	PhaseMerged     Phase = "Merged"

	PhaseBackportPlanning      Phase = "BackportPlanning"
	PhaseBackportBotRequested  Phase = "BackportBotRequested"
	PhaseBackportImplementing  Phase = "BackportImplementing"
	PhaseBackportCIWaiting     Phase = "BackportCIWaiting"
	PhaseBackportReviewWaiting Phase = "BackportReviewWaiting"
	PhaseBackportMerged        Phase = "BackportMerged"

	PhaseClosing Phase = "Closing"
	PhaseDone    Phase = "Done"
)

type ActorState struct {
	ActorID   string    `json:"actorID"`
	Ticket    string    `json:"ticket,omitempty"`
	Phase     Phase     `json:"phase"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`

	JIRA           *JIRAContext        `json:"jira,omitempty"`
	Implementation *ImplementationState `json:"implementation,omitempty"`
	PRs            map[string]*PRState  `json:"prs,omitempty"`
	Backports      *BackportState       `json:"backports,omitempty"`
	Retries        *RetryState          `json:"retries,omitempty"`
	Blockers       *BlockerInfo         `json:"blockers,omitempty"`

	ProcessedEvents map[string]bool `json:"processedEvents,omitempty"`
	Events          []EventRecord   `json:"events"`
	Config          *ActorConfig    `json:"config,omitempty"`
}

type JIRAContext struct {
	Key                string   `json:"key"`
	Type               string   `json:"type"`
	Summary            string   `json:"summary"`
	Description        string   `json:"description"`
	AcceptanceCriteria string   `json:"acceptanceCriteria,omitempty"`
	Status             string   `json:"status"`
	Priority           string   `json:"priority"`
	Assignee           string   `json:"assignee"`
	TargetVersions     []string `json:"targetVersions,omitempty"`
	EmbargoStatus      string   `json:"embargoStatus,omitempty"`
	Labels             []string `json:"labels,omitempty"`
	UpdatedAt          time.Time `json:"updatedAt"`
}

type ImplementationState struct {
	Plan          string    `json:"plan"`
	FilesToModify []string  `json:"filesToModify"`
	TestsNeeded   []string  `json:"testsNeeded"`
	Branch        string    `json:"branch"`
	AttemptCount  int       `json:"attemptCount"`
	LastAttemptAt time.Time `json:"lastAttemptAt,omitempty"`
	LastError     string    `json:"lastError,omitempty"`
}

type PRState struct {
	Repo       string    `json:"repo"`
	Number     int       `json:"number"`
	Branch     string    `json:"branch"`
	BaseBranch string    `json:"baseBranch"`
	HeadSHA    string    `json:"headSHA"`
	URL        string    `json:"url"`
	CreatedAt  time.Time `json:"createdAt"`

	CIStatus       string            `json:"ciStatus"`
	CheckRuns      map[string]string `json:"checkRuns,omitempty"`
	LastCIUpdateAt time.Time         `json:"lastCIUpdateAt,omitempty"`

	HasApproval     bool           `json:"hasApproval"`
	Reviewers       []string       `json:"reviewers,omitempty"`
	Reviews         []ReviewRecord `json:"reviews,omitempty"`
	ThreadsOpen     int            `json:"threadsOpen"`
	ThreadsResolved int            `json:"threadsResolved"`

	Conclusion string    `json:"conclusion"`
	MergedAt   time.Time `json:"mergedAt,omitempty"`
}

type ReviewRecord struct {
	ID          int64           `json:"id"`
	Reviewer    string          `json:"reviewer"`
	State       string          `json:"state"`
	SubmittedAt time.Time       `json:"submittedAt"`
	Body        string          `json:"body,omitempty"`
	Comments    []ReviewComment `json:"comments,omitempty"`
}

type ReviewComment struct {
	ID       int64  `json:"id"`
	Path     string `json:"path"`
	Line     int    `json:"line"`
	Body     string `json:"body"`
	Resolved bool   `json:"resolved"`
}

type BackportState struct {
	RequiredBranches  []string          `json:"requiredBranches"`
	CompletedBranches []string          `json:"completedBranches"`
	CurrentBranch     string            `json:"currentBranch,omitempty"`
	Strategy          map[string]string `json:"strategy,omitempty"`
	ConflictFiles     []string          `json:"conflictFiles,omitempty"`
}

type RetryState struct {
	Implementation  int       `json:"implementation"`
	CIFix           int       `json:"ciFix"`
	ReviewResponse  int       `json:"reviewResponse"`
	BackportAttempt int       `json:"backportAttempt"`
	LastRetryAt     time.Time `json:"lastRetryAt,omitempty"`

	MaxImplementation  int `json:"maxImplementation"`
	MaxCIFix           int `json:"maxCIFix"`
	MaxReviewResponse  int `json:"maxReviewResponse"`
	MaxBackportAttempt int `json:"maxBackportAttempt"`
}

type BlockerInfo struct {
	Reason    string    `json:"reason"`
	Details   []string  `json:"details,omitempty"`
	BlockedAt time.Time `json:"blockedAt"`
	CommentID int64     `json:"commentID,omitempty"`
}

type EventRecord struct {
	Timestamp time.Time `json:"timestamp"`
	EventID   string    `json:"eventID"`
	Source    string    `json:"source"`
	Type      string    `json:"type"`
	Phase     Phase     `json:"phase"`
	Decision  string    `json:"decision"`
	Result    string    `json:"result"`
}

type ActorConfig struct {
	AutoMerge         bool   `json:"autoMerge"`
	AutoMergeStrategy string `json:"autoMergeStrategy,omitempty"`

	MaxImplementationRetries int `json:"maxImplementationRetries,omitempty"`
	MaxCIFixRetries          int `json:"maxCIFixRetries,omitempty"`

	BackportStrategy string   `json:"backportStrategy,omitempty"`
	BackportBranches []string `json:"backportBranches,omitempty"`

	MaxAICostUSD   float64 `json:"maxAICostUSD,omitempty"`
	CurrentCostUSD float64 `json:"currentCostUSD,omitempty"`

	CITimeoutMinutes  int `json:"ciTimeoutMinutes,omitempty"`
	ReviewTimeoutDays int `json:"reviewTimeoutDays,omitempty"`
	TriageTimeoutDays int `json:"triageTimeoutDays,omitempty"`
}

func LoadState(path string) (*ActorState, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return newEmptyState(), nil
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
	if state.PRs == nil {
		state.PRs = make(map[string]*PRState)
	}
	if state.ProcessedEvents == nil {
		state.ProcessedEvents = make(map[string]bool)
	}

	return &state, nil
}

func newEmptyState() *ActorState {
	return &ActorState{
		Events:          []EventRecord{},
		PRs:             make(map[string]*PRState),
		ProcessedEvents: make(map[string]bool),
	}
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

func (s *ActorState) AddEvent(eventID, source, eventType, decision, result string) {
	s.Events = append(s.Events, EventRecord{
		Timestamp: time.Now(),
		EventID:   eventID,
		Source:    source,
		Type:      eventType,
		Phase:     s.Phase,
		Decision:  decision,
		Result:    result,
	})
	if eventID != "" {
		s.ProcessedEvents[eventID] = true
	}
	s.UpdatedAt = time.Now()
}

func (s *ActorState) IsEventProcessed(eventID string) bool {
	if eventID == "" {
		return false
	}
	return s.ProcessedEvents[eventID]
}

func (s *ActorState) GetMainPR() *PRState {
	if s.Implementation != nil && s.Implementation.Branch != "" {
		return s.PRs[s.Implementation.Branch]
	}
	return nil
}

func (s *ActorState) GetBackportPR(branch string) *PRState {
	return s.PRs[branch]
}

func (s *ActorState) IncrementRetry(operation string) {
	if s.Retries == nil {
		s.Retries = &RetryState{
			MaxImplementation:  3,
			MaxCIFix:           3,
			MaxReviewResponse:  3,
			MaxBackportAttempt: 2,
		}
	}
	switch operation {
	case "implementation":
		s.Retries.Implementation++
	case "ci-fix":
		s.Retries.CIFix++
	case "review-response":
		s.Retries.ReviewResponse++
	case "backport":
		s.Retries.BackportAttempt++
	}
	s.Retries.LastRetryAt = time.Now()
}

func (s *ActorState) HasExceededRetryLimit(operation string) bool {
	if s.Retries == nil {
		return false
	}
	switch operation {
	case "implementation":
		return s.Retries.Implementation >= s.Retries.MaxImplementation
	case "ci-fix":
		return s.Retries.CIFix >= s.Retries.MaxCIFix
	case "review-response":
		return s.Retries.ReviewResponse >= s.Retries.MaxReviewResponse
	case "backport":
		return s.Retries.BackportAttempt >= s.Retries.MaxBackportAttempt
	}
	return false
}

func (s *ActorState) SetBlocker(reason string, details []string) {
	s.Blockers = &BlockerInfo{
		Reason:    reason,
		Details:   details,
		BlockedAt: time.Now(),
	}
}

func (s *ActorState) ClearBlocker() {
	s.Blockers = nil
}
