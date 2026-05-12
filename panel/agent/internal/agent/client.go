package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

type Client interface {
	Register(ctx context.Context, report ReportRequest) error
	Report(ctx context.Context, report ReportRequest) error
	FetchTasks(ctx context.Context, nodeID string) ([]Task, error)
	SubmitTaskResult(ctx context.Context, taskID string, result TaskResult) error
}

type HTTPClient struct {
	baseURL string
	token   string
	client  *http.Client
}

func NewHTTPClient(cfg Config) *HTTPClient {
	return &HTTPClient{
		baseURL: cfg.ControllerURL,
		token:   cfg.ControllerToken,
		client:  &http.Client{Timeout: 10 * time.Second},
	}
}

func (c *HTTPClient) Register(ctx context.Context, report ReportRequest) error {
	req := RegisterRequest{ID: report.ID, Name: report.Name, Role: report.Role, Hostname: report.Hostname}
	return c.do(ctx, http.MethodPost, "/api/v1/agent/register", req, nil)
}

func (c *HTTPClient) Report(ctx context.Context, report ReportRequest) error {
	return c.do(ctx, http.MethodPost, "/api/v1/agent/report", report, nil)
}

func (c *HTTPClient) FetchTasks(ctx context.Context, nodeID string) ([]Task, error) {
	path := "/api/v1/agent/tasks?node_id=" + url.QueryEscape(nodeID)
	var tasks []Task
	err := c.do(ctx, http.MethodGet, path, nil, &tasks)
	return tasks, err
}

func (c *HTTPClient) SubmitTaskResult(ctx context.Context, taskID string, result TaskResult) error {
	return c.do(ctx, http.MethodPost, "/api/v1/agent/tasks/"+url.PathEscape(taskID)+"/result", result, nil)
}

func (c *HTTPClient) do(ctx context.Context, method, path string, body any, out any) error {
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("controller request failed: %w", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return err
	}
	var envelope APIResponse
	if err := json.Unmarshal(raw, &envelope); err != nil {
		return fmt.Errorf("invalid controller response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 || !envelope.OK {
		if envelope.Error != nil {
			return fmt.Errorf("%s: %s", envelope.Error.Code, RedactString(envelope.Error.Message, c.token))
		}
		return fmt.Errorf("controller returned status %d", resp.StatusCode)
	}
	if out != nil && len(envelope.Data) > 0 {
		if err := json.Unmarshal(envelope.Data, out); err != nil {
			return err
		}
	}
	return nil
}
