# DDNS

DDNS is an integrated Entry/Node capability rather than a top-level primary workflow.

## Usage

Entries can enable DDNS fields:

- provider
- domain
- record type
- token reference

Agent writes DDNS config to:

- `/etc/edge-tunnel/agent/ddns.json`

## Provider Strategy

The first MVP focuses on safe config landing and webhook-style integration points. Provider-specific sync behavior can be expanded after real deployment feedback.

## Secret Handling

DDNS tokens should be stored as references whenever possible. Task outputs and errors redact token-like values.
