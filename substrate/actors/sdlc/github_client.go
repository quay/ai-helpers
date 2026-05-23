package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

type GitHubClient struct {
	token      string
	httpClient *http.Client
}

func NewGitHubClient() *GitHubClient {
	token := os.Getenv("GITHUB_TOKEN")
	if token == "" {
		return nil
	}
	return &GitHubClient{
		token:      token,
		httpClient: http.DefaultClient,
	}
}

type CheckRunDetail struct {
	Name       string `json:"name"`
	Conclusion string `json:"conclusion"`
	Status     string `json:"status"`
	HTMLURL    string `json:"html_url"`
	Output     struct {
		Title   string `json:"title"`
		Summary string `json:"summary"`
		Text    string `json:"text"`
	} `json:"output"`
}

func (c *GitHubClient) GetCheckRuns(ctx context.Context, repo, sha string) ([]CheckRunDetail, error) {
	parts := strings.SplitN(repo, "/", 2)
	if len(parts) != 2 {
		return nil, fmt.Errorf("invalid repo format: %s", repo)
	}

	url := fmt.Sprintf("https://api.github.com/repos/%s/commits/%s/check-runs", repo, sha)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	c.setAuth(req)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching check runs: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API returned %d: %s", resp.StatusCode, body)
	}

	var result struct {
		CheckRuns []CheckRunDetail `json:"check_runs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decoding check runs: %w", err)
	}
	return result.CheckRuns, nil
}

func (c *GitHubClient) PostPRComment(ctx context.Context, repo string, prNumber int, body string) error {
	parts := strings.SplitN(repo, "/", 2)
	if len(parts) != 2 {
		return fmt.Errorf("invalid repo format: %s", repo)
	}

	payload, err := json.Marshal(map[string]string{"body": body})
	if err != nil {
		return err
	}

	url := fmt.Sprintf("https://api.github.com/repos/%s/issues/%d/comments", repo, prNumber)
	req, err := http.NewRequestWithContext(ctx, "POST", url, strings.NewReader(string(payload)))
	if err != nil {
		return err
	}
	c.setAuth(req)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("posting comment: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("GitHub API returned %d: %s", resp.StatusCode, respBody)
	}
	return nil
}

func (c *GitHubClient) setAuth(req *http.Request) {
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/vnd.github+json")
}
