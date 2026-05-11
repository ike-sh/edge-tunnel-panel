package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
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
