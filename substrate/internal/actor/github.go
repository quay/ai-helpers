package actor

import (
	"encoding/json"
	"fmt"
	"strings"
)

func ProcessGitHubEvent(h *Handler, state *ActorState, eventType string, payload []byte) (decision string, err error) {
	switch eventType {
	case "pull_request":
		return processPullRequest(h, state, payload)
	case "check_run":
		return processCheckRun(state, payload)
	case "check_suite":
		return processCheckSuite(state, payload)
	case "pull_request_review":
		return processPullRequestReview(h, state, payload)
	case "pull_request_review_thread":
		return processPullRequestReviewThread(state, payload)
	case "issue_comment":
		return processIssueComment(h, state, payload)
	default:
		return "ignored", nil
	}
}

func processPullRequest(h *Handler, state *ActorState, payload []byte) (string, error) {
	var event struct {
		Action      string `json:"action"`
		Number      int    `json:"number"`
		PullRequest struct {
			Number int `json:"number"`
			Head   struct {
				SHA string `json:"sha"`
				Ref string `json:"ref"`
			} `json:"head"`
			Base struct {
				Ref string `json:"ref"`
			} `json:"base"`
			Merged bool `json:"merged"`
		} `json:"pull_request"`
		Repository struct {
			FullName string `json:"full_name"`
		} `json:"repository"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling pull_request event: %w", err)
	}

	branch := event.PullRequest.Head.Ref
	if branch == "" {
		branch = "main"
	}

	baseBranch := event.PullRequest.Base.Ref
	isBackport := strings.HasPrefix(baseBranch, "redhat-") && isBackportPhase(state.Phase)

	switch event.Action {
	case "opened", "reopened":
		if isBackport {
			handleBackportPROpened(state, baseBranch, event.PullRequest.Number,
				event.Repository.FullName, event.PullRequest.Head.SHA)
			return fmt.Sprintf("backport PR opened for %s", baseBranch), nil
		}

		pr := state.PRs[branch]
		if pr == nil {
			pr = &PRState{}
			state.PRs[branch] = pr
		}
		pr.Repo = event.Repository.FullName
		pr.Number = event.PullRequest.Number
		pr.Branch = branch
		pr.BaseBranch = baseBranch
		pr.HeadSHA = event.PullRequest.Head.SHA
		pr.CIStatus = "pending"
		pr.Conclusion = "pending"
		state.Phase = PhaseCIWaiting
		return "initialized PR state", nil

	case "synchronize":
		if pr := state.PRs[branch]; pr != nil {
			pr.HeadSHA = event.PullRequest.Head.SHA
			pr.CIStatus = "pending"
		}
		if state.Phase == PhaseMergeReady || state.Phase == PhaseReviewWaiting {
			state.Phase = PhaseCIWaiting
		}
		return "updated HeadSHA", nil

	case "closed":
		pr := state.PRs[branch]
		if pr == nil {
			pr = state.PRs[baseBranch]
		}
		if pr != nil {
			if event.PullRequest.Merged {
				pr.Conclusion = "merged"
			} else {
				pr.Conclusion = "closed"
			}
		}

		if isBackport && event.PullRequest.Merged {
			handleBackportMerged(h, state)
			return fmt.Sprintf("backport PR merged for %s", baseBranch), nil
		}

		if event.PullRequest.Merged && state.JIRA != nil && len(state.JIRA.TargetVersions) > 0 {
			state.Phase = PhaseBackportPlanning
		} else if event.PullRequest.Merged {
			closeTicket(h, state)
		} else {
			state.Phase = PhaseDone
		}
		return fmt.Sprintf("PR %s", pr.Conclusion), nil

	default:
		return "ignored", nil
	}
}

func processCheckRun(state *ActorState, payload []byte) (string, error) {
	var event struct {
		Action   string `json:"action"`
		CheckRun struct {
			Name       string `json:"name"`
			Conclusion string `json:"conclusion"`
		} `json:"check_run"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling check_run event: %w", err)
	}

	if event.Action != "completed" {
		return "ignored", nil
	}

	pr := findActivePR(state)
	if pr == nil {
		return "ignored", nil
	}

	if pr.CheckRuns == nil {
		pr.CheckRuns = make(map[string]string)
	}
	pr.CheckRuns[event.CheckRun.Name] = event.CheckRun.Conclusion

	if event.CheckRun.Conclusion == "success" {
		pr.CIStatus = "passing"
	} else {
		pr.CIStatus = "failing"
	}
	transitionOnCIComplete(state)
	return fmt.Sprintf("CI check %s: %s", event.CheckRun.Name, event.CheckRun.Conclusion), nil
}

func processCheckSuite(state *ActorState, payload []byte) (string, error) {
	var event struct {
		Action     string `json:"action"`
		CheckSuite struct {
			Conclusion string `json:"conclusion"`
		} `json:"check_suite"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling check_suite event: %w", err)
	}

	if event.Action != "completed" {
		return "ignored", nil
	}

	pr := findActivePR(state)
	if pr == nil {
		return "ignored", nil
	}

	if event.CheckSuite.Conclusion == "success" {
		pr.CIStatus = "passing"
	} else {
		pr.CIStatus = "failing"
	}
	transitionOnCIComplete(state)
	return fmt.Sprintf("CI status: %s", pr.CIStatus), nil
}

type parsedReview struct {
	ID       int64           `json:"id"`
	User     string          `json:"user"`
	State    string          `json:"state"`
	Body     string          `json:"body"`
	Comments []ReviewComment `json:"comments"`
}

func processPullRequestReview(h *Handler, state *ActorState, payload []byte) (string, error) {
	var event struct {
		Action string `json:"action"`
		Review struct {
			ID   int64  `json:"id"`
			User struct {
				Login string `json:"login"`
			} `json:"user"`
			State string `json:"state"`
			Body  string `json:"body"`
		} `json:"review"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling pull_request_review event: %w", err)
	}

	if event.Action != "submitted" {
		return "ignored", nil
	}

	pr := findActivePR(state)
	if pr == nil {
		return "ignored", nil
	}

	review := &parsedReview{
		ID:    event.Review.ID,
		User:  event.Review.User.Login,
		State: event.Review.State,
		Body:  event.Review.Body,
	}

	switch event.Review.State {
	case "approved":
		pr.HasApproval = true
		if state.Phase == PhaseBackportReviewWaiting {
			handleBackportMerged(h, state)
			return "backport approved and merged", nil
		}
		transitionIfMergeReady(state)
		return "approval received", nil
	case "changes_requested":
		categorizeAndTransition(h, state, review)
		return "changes requested, feedback categorized", nil
	case "dismissed":
		pr.HasApproval = false
		if state.Phase == PhaseChangesRequested {
			state.Phase = PhaseReviewWaiting
		}
		return "review dismissed", nil
	default:
		return "ignored", nil
	}
}

func processPullRequestReviewThread(state *ActorState, payload []byte) (string, error) {
	var event struct {
		Action string `json:"action"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling review thread event: %w", err)
	}

	pr := findActivePR(state)
	if pr == nil {
		return "ignored", nil
	}

	switch event.Action {
	case "resolved":
		if pr.ThreadsOpen > 0 {
			pr.ThreadsOpen--
		}
		pr.ThreadsResolved++
		if pr.ThreadsOpen == 0 && state.Phase == PhaseChangesRequested {
			transitionIfMergeReady(state)
		}
		return fmt.Sprintf("thread resolved (%d open)", pr.ThreadsOpen), nil
	case "unresolved":
		pr.ThreadsOpen++
		return fmt.Sprintf("thread unresolved (%d open)", pr.ThreadsOpen), nil
	default:
		return "ignored", nil
	}
}

func processIssueComment(h *Handler, state *ActorState, payload []byte) (string, error) {
	var event struct {
		Action  string `json:"action"`
		Comment struct {
			User struct {
				Login string `json:"login"`
			} `json:"user"`
			Body string `json:"body"`
		} `json:"comment"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling issue_comment event: %w", err)
	}

	if event.Action != "created" {
		return "ignored", nil
	}

	if strings.HasSuffix(event.Comment.User.Login, "[bot]") {
		return "ignored (bot comment)", nil
	}

	body := strings.TrimSpace(event.Comment.Body)

	if !strings.HasPrefix(body, "/actor-") {
		if state.Phase == PhaseClarificationNeeded {
			return handleClarificationReply(h, state, body)
		}
		return "ignored (not a command)", nil
	}

	parts := strings.SplitN(body, " ", 2)
	command := parts[0]
	args := ""
	if len(parts) > 1 {
		args = strings.TrimSpace(parts[1])
	}

	_, err := processActorCommand(state, command, args)
	if err != nil {
		return fmt.Sprintf("command error: %s", err.Error()), err
	}

	return fmt.Sprintf("command processed: %s", command), nil
}

func findActivePR(state *ActorState) *PRState {
	if pr := state.GetMainPR(); pr != nil {
		return pr
	}
	for _, pr := range state.PRs {
		return pr
	}
	return nil
}
