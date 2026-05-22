package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

type JIRAClient struct {
	baseURL    string
	user       string
	token      string
	httpClient *http.Client
}

func NewJIRAClient() *JIRAClient {
	baseURL := os.Getenv("JIRA_BASE_URL")
	user := os.Getenv("JIRA_USER")
	token := os.Getenv("JIRA_API_TOKEN")

	if baseURL == "" || user == "" || token == "" {
		return nil
	}

	return &JIRAClient{
		baseURL: baseURL,
		user:    user,
		token:   token,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

type JIRAIssue struct {
	Key    string          `json:"key"`
	Fields json.RawMessage `json:"fields"`
}

func (c *JIRAClient) GetIssue(key string) (*JIRAIssue, error) {
	req, err := http.NewRequest("GET", fmt.Sprintf("%s/rest/api/3/issue/%s", c.baseURL, key), nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}
	c.setAuth(req)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching issue: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("JIRA API returned %d: %s", resp.StatusCode, body)
	}

	var issue JIRAIssue
	if err := json.NewDecoder(resp.Body).Decode(&issue); err != nil {
		return nil, fmt.Errorf("decoding issue: %w", err)
	}
	return &issue, nil
}

func (c *JIRAClient) AddComment(key, text string) error {
	body := adfFromText(text)

	payload, err := json.Marshal(map[string]any{"body": body})
	if err != nil {
		return fmt.Errorf("marshaling comment: %w", err)
	}

	req, err := http.NewRequest("POST", fmt.Sprintf("%s/rest/api/3/issue/%s/comment", c.baseURL, key), bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("creating request: %w", err)
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
		return fmt.Errorf("JIRA API returned %d: %s", resp.StatusCode, respBody)
	}
	return nil
}

func (c *JIRAClient) TransitionIssue(key, transitionID string) error {
	payload, err := json.Marshal(map[string]any{
		"transition": map[string]string{"id": transitionID},
	})
	if err != nil {
		return fmt.Errorf("marshaling transition: %w", err)
	}

	req, err := http.NewRequest("POST", fmt.Sprintf("%s/rest/api/3/issue/%s/transitions", c.baseURL, key), bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("creating request: %w", err)
	}
	c.setAuth(req)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("transitioning issue: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("JIRA API returned %d: %s", resp.StatusCode, respBody)
	}
	return nil
}

func (c *JIRAClient) AssignIssue(key, accountID string) error {
	payload, err := json.Marshal(map[string]string{"accountId": accountID})
	if err != nil {
		return fmt.Errorf("marshaling assignee: %w", err)
	}

	req, err := http.NewRequest("PUT", fmt.Sprintf("%s/rest/api/3/issue/%s/assignee", c.baseURL, key), bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("creating request: %w", err)
	}
	c.setAuth(req)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("assigning issue: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("JIRA API returned %d: %s", resp.StatusCode, respBody)
	}
	return nil
}

func (c *JIRAClient) setAuth(req *http.Request) {
	req.SetBasicAuth(c.user, c.token)
	req.Header.Set("Accept", "application/json")
}

// adfFromText wraps plain text in a minimal Atlassian Document Format structure
// required by JIRA Cloud API v3 for comment bodies.
func adfFromText(text string) map[string]any {
	return map[string]any{
		"version": 1,
		"type":    "doc",
		"content": []map[string]any{
			{
				"type": "paragraph",
				"content": []map[string]any{
					{
						"type": "text",
						"text": text,
					},
				},
			},
		},
	}
}
