package actor

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
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

func (c *GitHubClient) doRequest(ctx context.Context, method, path string, body any, expectedStatus int, result any) error {
	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshaling request: %w", err)
		}
		reqBody = bytes.NewReader(data)
	}

	url := "https://api.github.com" + path
	req, err := http.NewRequestWithContext(ctx, method, url, reqBody)
	if err != nil {
		return fmt.Errorf("creating request: %w", err)
	}
	c.setAuth(req)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != expectedStatus {
		return fmt.Errorf("GitHub API returned %d: %s", resp.StatusCode, respBody)
	}

	if result != nil {
		return json.Unmarshal(respBody, result)
	}
	return nil
}

func (c *GitHubClient) GetCheckRuns(ctx context.Context, repo, sha string) ([]CheckRunDetail, error) {
	var result struct {
		CheckRuns []CheckRunDetail `json:"check_runs"`
	}

	path := fmt.Sprintf("/repos/%s/commits/%s/check-runs", repo, sha)
	if err := c.doRequest(ctx, "GET", path, nil, http.StatusOK, &result); err != nil {
		return nil, fmt.Errorf("fetching check runs: %w", err)
	}
	return result.CheckRuns, nil
}

func (c *GitHubClient) PostPRComment(ctx context.Context, repo string, prNumber int, body string) error {
	path := fmt.Sprintf("/repos/%s/issues/%d/comments", repo, prNumber)
	return c.doRequest(ctx, "POST", path, map[string]string{"body": body}, http.StatusCreated, nil)
}

func (c *GitHubClient) setAuth(req *http.Request) {
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/vnd.github+json")
}
