package main

import (
	"encoding/json"
	"fmt"
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
		return "ignored", nil
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
			} `json:"head"`
			Merged bool `json:"merged"`
		} `json:"pull_request"`
		Repository struct {
			FullName string `json:"full_name"`
		} `json:"repository"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return "", fmt.Errorf("while unmarshaling pull_request event: %w", err)
	}

	switch event.Action {
	case "opened", "reopened":
		if state.PR == nil {
			state.PR = &PRState{}
		}
		state.PR.Repo = event.Repository.FullName
		state.PR.Number = event.PullRequest.Number
		state.PR.HeadSHA = event.PullRequest.Head.SHA
		state.PR.CIStatus = "pending"
		state.PR.Conclusion = "pending"
		state.Phase = "pr-open"
		return "initialized PR state", nil

	case "synchronize":
		if state.PR != nil {
			state.PR.HeadSHA = event.PullRequest.Head.SHA
			state.PR.CIStatus = "pending"
		}
		return "updated HeadSHA", nil

	case "closed":
		if state.PR != nil {
			if event.PullRequest.Merged {
				state.PR.Conclusion = "merged"
			} else {
				state.PR.Conclusion = "closed"
			}
		}
		state.Phase = "done"
		return fmt.Sprintf("PR %s", state.PR.Conclusion), nil

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

	if state.PR != nil {
		if event.CheckRun.Conclusion == "success" {
			state.PR.CIStatus = "passing"
			return "CI status: passing", nil
		}
		state.PR.CIStatus = "failing"
		return "CI status: failing", nil
	}

	return "ignored", nil
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

	if state.PR != nil {
		if event.CheckSuite.Conclusion == "success" {
			state.PR.CIStatus = "passing"
			return "CI status: passing", nil
		}
		state.PR.CIStatus = "failing"
		return "CI status: failing", nil
	}

	return "ignored", nil
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

	if state.PR == nil {
		return "ignored", nil
	}

	switch event.Review.State {
	case "approved":
		state.PR.HasApproval = true
		return "approval received", nil
	case "changes_requested":
		state.PR.Conclusion = "actionable"
		return "changes requested", nil
	default:
		return "ignored", nil
	}
}
