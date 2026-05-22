package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

func ProcessGitHubEvent(state *ActorState, eventType string, payload []byte) (decision string, err error) {
	switch eventType {
	case "pull_request":
		return processPullRequest(state, payload)
	case "check_run":
		return processCheckRun(state, payload)
	case "check_suite":
		return processCheckSuite(state, payload)
	case "pull_request_review":
		return processPullRequestReview(state, payload)
	case "issue_comment":
		return processIssueComment(state, payload)
	default:
		return "ignored", nil
	}
}

func processPullRequest(state *ActorState, payload []byte) (string, error) {
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

	switch event.Action {
	case "opened", "reopened":
		pr := state.PRs[branch]
		if pr == nil {
			pr = &PRState{}
			state.PRs[branch] = pr
		}
		pr.Repo = event.Repository.FullName
		pr.Number = event.PullRequest.Number
		pr.Branch = branch
		pr.BaseBranch = event.PullRequest.Base.Ref
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
		return "updated HeadSHA", nil

	case "closed":
		if pr := state.PRs[branch]; pr != nil {
			if event.PullRequest.Merged {
				pr.Conclusion = "merged"
			} else {
				pr.Conclusion = "closed"
			}
		}
		state.Phase = PhaseDone
		return fmt.Sprintf("PR %s", state.PRs[branch].Conclusion), nil

	default:
		return "ignored", nil
	}
}

func processCheckRun(state *ActorState, payload []byte) (string, error) {
	var event struct {
		Action   string `json:"action"`
		CheckRun struct {
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

	if event.CheckRun.Conclusion == "success" {
		pr.CIStatus = "passing"
		return "CI status: passing", nil
	}
	pr.CIStatus = "failing"
	return "CI status: failing", nil
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
		return "CI status: passing", nil
	}
	pr.CIStatus = "failing"
	return "CI status: failing", nil
}

func processPullRequestReview(state *ActorState, payload []byte) (string, error) {
	var event struct {
		Review struct {
			State string `json:"state"`
		} `json:"review"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling pull_request_review event: %w", err)
	}

	pr := findActivePR(state)
	if pr == nil {
		return "ignored", nil
	}

	switch event.Review.State {
	case "approved":
		pr.HasApproval = true
		return "approval received", nil
	case "changes_requested":
		pr.Conclusion = "actionable"
		return "changes requested", nil
	default:
		return "ignored", nil
	}
}

func processIssueComment(state *ActorState, payload []byte) (string, error) {
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

	// Only handle created comments
	if event.Action != "created" {
		return "ignored", nil
	}

	// Ignore bot comments
	if strings.HasSuffix(event.Comment.User.Login, "[bot]") {
		return "ignored (bot comment)", nil
	}

	// Check if comment contains an actor command
	body := strings.TrimSpace(event.Comment.Body)
	if !strings.HasPrefix(body, "/actor-") {
		return "ignored (not a command)", nil
	}

	// Parse command and args
	parts := strings.SplitN(body, " ", 2)
	command := parts[0]
	args := ""
	if len(parts) > 1 {
		args = strings.TrimSpace(parts[1])
	}

	// Process the command
	_, err := processActorCommand(state, command, args)
	if err != nil {
		return fmt.Sprintf("command error: %s", err.Error()), err
	}

	return fmt.Sprintf("command processed: %s", command), nil
}

// findActivePR returns the first PR in the map, used by handlers that
// don't have branch context from the payload. When only one PR is
// tracked (the common case in Phase 1), this returns it.
func findActivePR(state *ActorState) *PRState {
	if pr := state.GetMainPR(); pr != nil {
		return pr
	}
	for _, pr := range state.PRs {
		return pr
	}
	return nil
}
