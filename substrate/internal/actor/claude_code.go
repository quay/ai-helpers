package actor

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/quay/ai-helpers/substrate/internal/envutil"
)

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
		binaryPath: envutil.Or("CLAUDE_BINARY", "claude"),
		repoDir:    RepoDir(),
	}
}

type invokeOpts struct {
	prompt     string
	continuing bool
}

func (c *ClaudeCodeClient) invoke(ctx context.Context, opts invokeOpts) (string, error) {
	slog.Info("invoking claude",
		slog.String("binary", c.binaryPath),
		slog.Bool("continue", opts.continuing),
		slog.String("prompt_prefix", truncate(opts.prompt, 100)))

	args := []string{"-p", opts.prompt, "--dangerously-skip-permissions"}
	if opts.continuing {
		args = append(args, "--continue")
	}

	result, err := runCommand(ctx, c.repoDir, c.binaryPath, args...)
	if err != nil {
		return "", fmt.Errorf("claude invocation failed (exit %d): err=%v stdout=%s stderr=%s",
			result.ExitCode, err, truncate(result.Stdout, 200), truncate(result.Stderr, 200))
	}
	return result.Stdout, nil
}

func (c *ClaudeCodeClient) invokeJSON(ctx context.Context, prompt string, out any) error {
	stdout, err := c.invoke(ctx, invokeOpts{prompt: prompt})
	if err != nil {
		return err
	}
	cleaned := extractJSON(stdout)
	if err := json.Unmarshal([]byte(cleaned), out); err != nil {
		return fmt.Errorf("parsing claude output as JSON: %w\nraw output: %s", err, truncate(stdout, 500))
	}
	return nil
}

func (c *ClaudeCodeClient) Plan(ctx context.Context, jira *JIRAContext) (*PlanResult, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()

	prompt := fmt.Sprintf(`Analyze this codebase and create an implementation plan for JIRA ticket %s (%s): %s

Description:
%s

Output ONLY a JSON object with these fields:
- plan: string (detailed implementation steps)
- filesToModify: []string (file paths to change)
- testsNeeded: []string (test files to create/modify)
- difficulty: string (easy | medium | hard)`, jira.Key, jira.Type, jira.Summary, jira.Description)

	var result PlanResult
	if err := c.invokeJSON(ctx, prompt, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

func (c *ClaudeCodeClient) Implement(ctx context.Context, jira *JIRAContext, plan *PlanResult) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()

	prompt := fmt.Sprintf(`Implement the following plan for %s: %s

Plan:
%s

Files to modify: %s
Tests needed: %s

Requirements:
- Edit the necessary files
- Write or update tests
- Run tests and fix any failures
- Commit all changes with message "%s: %s"
- Do NOT push`, jira.Key, jira.Summary,
		plan.Plan,
		strings.Join(plan.FilesToModify, ", "),
		strings.Join(plan.TestsNeeded, ", "),
		jira.Key, jira.Summary)

	_, err := c.invoke(ctx, invokeOpts{prompt: prompt, continuing: true})
	return err
}

func (c *ClaudeCodeClient) AnalyzeCI(ctx context.Context, jira *JIRAContext, failingChecks []string) (*CIAnalysisResult, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()

	prompt := fmt.Sprintf(`CI has failed on PR for %s: %s

Failing checks:
%s

Analyze the failure and output ONLY a JSON object:
- rootCause: string (what failed and why)
- fixable: bool (can this be fixed by code changes in this PR?)
- fixApproach: string (how to fix it, if fixable)
- confidence: float (0.0 to 1.0)`, jira.Key, jira.Summary, strings.Join(failingChecks, "\n"))

	var result CIAnalysisResult
	if err := c.invokeJSON(ctx, prompt, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

func (c *ClaudeCodeClient) FixCI(ctx context.Context, analysis *CIAnalysisResult) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	prompt := fmt.Sprintf(`Fix the following CI failure:

Root cause: %s
Fix approach: %s

Edit the necessary files to fix this issue. Run tests to verify.
Commit the fix with message "fix: %s".
Do NOT push.`, analysis.RootCause, analysis.FixApproach, analysis.RootCause)

	_, err := c.invoke(ctx, invokeOpts{prompt: prompt, continuing: true})
	return err
}

func (c *ClaudeCodeClient) AddressFeedback(ctx context.Context, jira *JIRAContext, pr *PRState) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	var fb strings.Builder
	for _, review := range pr.Reviews {
		if review.State != "changes_requested" {
			continue
		}
		fb.WriteString(fmt.Sprintf("Reviewer: %s\n", review.Reviewer))
		if review.Body != "" {
			fb.WriteString(fmt.Sprintf("Summary: %s\n", review.Body))
		}
		for _, c := range review.Comments {
			fb.WriteString(fmt.Sprintf("- %s:%d: %s\n", c.Path, c.Line, c.Body))
		}
		fb.WriteString("\n")
	}

	prompt := fmt.Sprintf(`Address the following review feedback on PR #%d for %s:

%s
Implement all blocking requests and easy suggestions.
Run tests after changes. Commit with message "%s: address review feedback".
Do NOT push.`, pr.Number, jira.Key, fb.String(), jira.Key)

	_, err := c.invoke(ctx, invokeOpts{prompt: prompt, continuing: true})
	return err
}

func (c *ClaudeCodeClient) CheckClarification(ctx context.Context, commentBody string) (bool, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	prompt := fmt.Sprintf(`A reviewer was asked for clarification and replied:

"%s"

Does this reply provide enough information to proceed with implementation?
Output ONLY a JSON object: {"resolved": true/false, "reason": "..."}`, commentBody)

	var result struct {
		Resolved bool   `json:"resolved"`
		Reason   string `json:"reason"`
	}
	if err := c.invokeJSON(ctx, prompt, &result); err != nil {
		return false, err
	}
	return result.Resolved, nil
}

func extractJSON(s string) string {
	start := strings.IndexByte(s, '{')
	if start == -1 {
		return s
	}
	depth := 0
	for i := start; i < len(s); i++ {
		switch s[i] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return s[start : i+1]
			}
		}
	}
	return s[start:]
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
