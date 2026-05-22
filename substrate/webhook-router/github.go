package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

func verifyGitHubSignature(payload []byte, signatureHeader, secret string) error {
	if signatureHeader == "" {
		return fmt.Errorf("missing X-Hub-Signature-256 header")
	}

	parts := strings.SplitN(signatureHeader, "=", 2)
	if len(parts) != 2 || parts[0] != "sha256" {
		return fmt.Errorf("invalid signature format: expected sha256=<hex>")
	}

	expectedSig, err := hex.DecodeString(parts[1])
	if err != nil {
		return fmt.Errorf("invalid hex signature: %w", err)
	}

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	actualSig := mac.Sum(nil)

	if !hmac.Equal(expectedSig, actualSig) {
		return fmt.Errorf("signature mismatch")
	}

	return nil
}

func parseGitHubEvent(eventType string, payload []byte) (actorID string, action string, err error) {
	var baseEvent struct {
		Action     string `json:"action"`
		Repository struct {
			FullName string `json:"full_name"`
		} `json:"repository"`
	}

	if err := json.Unmarshal(payload, &baseEvent); err != nil {
		return "", "", fmt.Errorf("failed to parse base event: %w", err)
	}

	action = baseEvent.Action
	var prNumber int

	switch eventType {
	case "pull_request":
		var prEvent struct {
			Number int `json:"number"`
		}
		if err := json.Unmarshal(payload, &prEvent); err != nil {
			return "", "", fmt.Errorf("failed to parse pull_request event: %w", err)
		}
		prNumber = prEvent.Number

	case "check_run":
		var checkRunEvent struct {
			CheckRun struct {
				PullRequests []struct {
					Number int `json:"number"`
				} `json:"pull_requests"`
			} `json:"check_run"`
		}
		if err := json.Unmarshal(payload, &checkRunEvent); err != nil {
			return "", "", fmt.Errorf("failed to parse check_run event: %w", err)
		}
		if len(checkRunEvent.CheckRun.PullRequests) == 0 {
			return "", "", fmt.Errorf("check_run event has no associated pull requests")
		}
		prNumber = checkRunEvent.CheckRun.PullRequests[0].Number

	case "check_suite":
		var checkSuiteEvent struct {
			CheckSuite struct {
				PullRequests []struct {
					Number int `json:"number"`
				} `json:"pull_requests"`
			} `json:"check_suite"`
		}
		if err := json.Unmarshal(payload, &checkSuiteEvent); err != nil {
			return "", "", fmt.Errorf("failed to parse check_suite event: %w", err)
		}
		if len(checkSuiteEvent.CheckSuite.PullRequests) == 0 {
			return "", "", fmt.Errorf("check_suite event has no associated pull requests")
		}
		prNumber = checkSuiteEvent.CheckSuite.PullRequests[0].Number

	case "pull_request_review":
		var reviewEvent struct {
			PullRequest struct {
				Number int `json:"number"`
			} `json:"pull_request"`
		}
		if err := json.Unmarshal(payload, &reviewEvent); err != nil {
			return "", "", fmt.Errorf("failed to parse pull_request_review event: %w", err)
		}
		prNumber = reviewEvent.PullRequest.Number

	case "issue_comment":
		var commentEvent struct {
			Issue struct {
				Number      int `json:"number"`
				PullRequest *struct {
					URL string `json:"url"`
				} `json:"pull_request"`
			} `json:"issue"`
		}
		if err := json.Unmarshal(payload, &commentEvent); err != nil {
			return "", "", fmt.Errorf("failed to parse issue_comment event: %w", err)
		}
		if commentEvent.Issue.PullRequest == nil {
			return "", "", fmt.Errorf("issue_comment event is not on a pull request")
		}
		prNumber = commentEvent.Issue.Number

	default:
		return "", "", fmt.Errorf("unsupported event type: %s", eventType)
	}

	if prNumber == 0 {
		return "", "", fmt.Errorf("failed to extract PR number from %s event", eventType)
	}

	parts := strings.Split(baseEvent.Repository.FullName, "/")
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid repository full_name: %s", baseEvent.Repository.FullName)
	}
	owner, repo := parts[0], parts[1]

	actorID = sanitizeDNS1123(fmt.Sprintf("pr-%s-%s-%d", owner, repo, prNumber))
	return actorID, action, nil
}

var nonAlphanumeric = regexp.MustCompile(`[^a-z0-9-]+`)
var consecutiveDashes = regexp.MustCompile(`-+`)

func sanitizeDNS1123(s string) string {
	s = strings.ToLower(s)
	s = nonAlphanumeric.ReplaceAllString(s, "-")
	s = consecutiveDashes.ReplaceAllString(s, "-")
	s = strings.Trim(s, "-")
	if len(s) > 63 {
		s = s[:63]
	}
	s = strings.TrimRight(s, "-")
	return s
}
