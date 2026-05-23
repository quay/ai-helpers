package actor

import "context"

type GitHubAPI interface {
	GetCheckRuns(ctx context.Context, repo, sha string) ([]CheckRunDetail, error)
	PostPRComment(ctx context.Context, repo string, prNumber int, body string) error
}

type JIRAAPI interface {
	GetIssue(key string) (*JIRAIssue, error)
	AddComment(key, text string) error
	TransitionIssue(key, transitionID string) error
	AssignIssue(key, accountID string) error
}

type ClaudeAPI interface {
	Plan(ctx context.Context, jira *JIRAContext) (*PlanResult, error)
	Implement(ctx context.Context, jira *JIRAContext, plan *PlanResult) error
	AnalyzeCI(ctx context.Context, jira *JIRAContext, failingChecks []string) (*CIAnalysisResult, error)
	FixCI(ctx context.Context, analysis *CIAnalysisResult) error
	AddressFeedback(ctx context.Context, jira *JIRAContext, pr *PRState) error
	CheckClarification(ctx context.Context, commentBody string) (bool, error)
}

type ATEAPI interface {
	SuspendSelf(actorID string)
	Close()
}

type GitOperations interface {
	Fetch(ctx context.Context, dir, branch string) error
	CheckoutNewBranch(ctx context.Context, dir, branch string) error
	Add(ctx context.Context, dir string) error
	Commit(ctx context.Context, dir, message string) error
	Push(ctx context.Context, dir, branch, token string) error
	EnsureRepo(ctx context.Context) error
}
