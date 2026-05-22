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
