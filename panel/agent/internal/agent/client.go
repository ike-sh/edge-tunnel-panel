package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Client struct {
	BaseURL string
	Token   string
	HTTP    *http.Client
}

func NewClient(cfg Config) Client {
	return Client{
		BaseURL: strings.TrimRight(cfg.ControllerURL, "/"),
		Token:   cfg.Token,
		HTTP:    &http.Client{Timeout: 10 * time.Second},
	}
}

func (c Client) Register(ctx context.Context, req RegisterRequest) error {
	return c.post(ctx, "/api/v1/agent/register", req)
}

func (c Client) Report(ctx context.Context, req ReportRequest) error {
	return c.post(ctx, "/api/v1/agent/report", req)
}

func (c Client) GetTasks(ctx context.Context, nodeID string) ([]Task, error) {
	endpoint := "/api/v1/agent/tasks?node_id=" + url.QueryEscape(nodeID) + "&limit=1"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.BaseURL+endpoint, nil)
	if err != nil {
		return nil, err
	}
	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("controller returned %s", resp.Status)
	}
	var tasks []Task
	if err := json.NewDecoder(resp.Body).Decode(&tasks); err != nil {
		return nil, err
	}
	return tasks, nil
}

func (c Client) ReportTaskResult(ctx context.Context, taskID int64, req TaskResultRequest) error {
	return c.post(ctx, fmt.Sprintf("/api/v1/agent/tasks/%d/result", taskID), req)
}

func (c Client) post(ctx context.Context, path string, body any) error {
	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+path, bytes.NewReader(RedactJSONBytes(raw)))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("controller returned %s", resp.Status)
	}
	return nil
}
