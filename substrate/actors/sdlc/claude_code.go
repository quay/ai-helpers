package main

import (
	"context"
	"log/slog"
)

var claudeClient *ClaudeCodeClient

type ClaudeCodeClient struct {
	binaryPath string
	repoDir    string
}

type PlanResult struct {
	Plan          string   `json:"plan"`
	FilesToModify []string `json:"filesToModify"`
	TestsNeeded   []string `json:"testsNeeded"`
	Difficulty    string   `json:"difficulty"`
}

func NewClaudeCodeClient() *ClaudeCodeClient {
	return &ClaudeCodeClient{
		binaryPath: envOr("CLAUDE_BINARY", "claude"),
		repoDir:    repoDir(),
	}
}

// Plan invokes Claude Code to analyze the codebase and generate an implementation plan.
// STUB: returns a placeholder plan.
func (c *ClaudeCodeClient) Plan(ctx context.Context, jira *JIRAContext) (*PlanResult, error) {
	slog.Info("STUB: claude plan invocation",
		slog.String("ticket", jira.Key),
		slog.String("type", jira.Type),
		slog.String("summary", jira.Summary),
		slog.String("prompt", buildPlanPrompt(jira)))

	return &PlanResult{
		Plan:          "STUB: placeholder implementation plan for " + jira.Key,
		FilesToModify: []string{"placeholder.go"},
		TestsNeeded:   []string{"placeholder_test.go"},
		Difficulty:    "medium",
	}, nil
}

// Implement invokes Claude Code to write code and run tests based on the plan.
// Claude Code handles the full edit→test→fix loop internally.
// STUB: logs what it would do and returns nil (success).
func (c *ClaudeCodeClient) Implement(ctx context.Context, jira *JIRAContext, plan *PlanResult) error {
	slog.Info("STUB: claude implement invocation",
		slog.String("ticket", jira.Key),
		slog.String("plan", plan.Plan),
		slog.String("prompt", buildImplementPrompt(jira, plan)))

	return nil
}

// AnalyzeCI invokes Claude Code to analyze CI failure logs and determine root cause.
// STUB: returns a fixable analysis.
func (c *ClaudeCodeClient) AnalyzeCI(ctx context.Context, jira *JIRAContext, failingChecks []string) (*CIAnalysisResult, error) {
	slog.Info("STUB: claude CI analysis invocation",
		slog.String("ticket", jira.Key),
		slog.Any("failingChecks", failingChecks))

	return &CIAnalysisResult{
		RootCause:   "STUB: placeholder CI failure analysis",
		Fixable:     true,
		FixApproach: "STUB: placeholder fix approach",
		Confidence:  0.9,
	}, nil
}

// FixCI invokes Claude Code to fix the CI failure based on analysis.
// Claude Code edits code, commits the fix.
// STUB: logs and returns nil (success).
func (c *ClaudeCodeClient) FixCI(ctx context.Context, analysis *CIAnalysisResult) error {
	slog.Info("STUB: claude CI fix invocation",
		slog.String("rootCause", analysis.RootCause),
		slog.String("approach", analysis.FixApproach))

	return nil
}

// AddressFeedback invokes Claude Code to implement review feedback changes.
// STUB: logs and returns nil (success).
func (c *ClaudeCodeClient) AddressFeedback(ctx context.Context, jira *JIRAContext, pr *PRState) error {
	slog.Info("STUB: claude address feedback invocation",
		slog.String("ticket", jira.Key),
		slog.Int("reviewCount", len(pr.Reviews)),
		slog.Int("threadsOpen", pr.ThreadsOpen))

	return nil
}

// CheckClarification invokes Claude Code to determine if a comment resolves a pending clarification.
// STUB: returns true (resolved).
func (c *ClaudeCodeClient) CheckClarification(ctx context.Context, commentBody string) (bool, error) {
	slog.Info("STUB: claude check clarification",
		slog.String("comment", commentBody))

	return true, nil
}

func buildPlanPrompt(jira *JIRAContext) string {
	return "Analyze the codebase and create an implementation plan for " +
		jira.Key + ": " + jira.Summary + "\n\n" +
		"Type: " + jira.Type + "\n" +
		"Description: " + jira.Description + "\n\n" +
		"Output a JSON plan with fields: plan, filesToModify, testsNeeded, difficulty"
}

func buildImplementPrompt(jira *JIRAContext, plan *PlanResult) string {
	return "Implement the following plan for " + jira.Key + ":\n\n" +
		plan.Plan + "\n\n" +
		"Edit the necessary files, run tests, and fix any failures. " +
		"Commit your changes when tests pass."
}
