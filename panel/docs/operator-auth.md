# Operator Auth

Leikwan Panel 2.1.0 separates the token used by Agents from the token used by human operators. This keeps node reporting isolated from Web/API operations such as creating Plans, queuing readonly tasks, recording manual snapshot metadata, or approving audit states.

## Token Types

`LEIKWAN_CONTROLLER_TOKEN` is the Agent token. It is used only by:

- `POST /api/v1/agent/register`
- `POST /api/v1/agent/report`
- `GET /api/v1/agent/tasks`
- `POST /api/v1/agent/tasks/:id/result`

`LEIKWAN_OPERATOR_TOKEN` is the Operator token. It is used by the Web UI and operator APIs for metadata-changing actions:

- Plan create, generate, regenerate, archive and mark
- Plan dry-run start, snapshot metadata, rollback metadata, verify and action review
- Readonly task create, cancel, retry, approve and reject

The two tokens are not interchangeable. Agent APIs reject the Operator token, and Operator APIs reject the Agent token.

## Startup Flags

```bash
leikwan-controller \
  --token "$LEIKWAN_CONTROLLER_TOKEN" \
  --operator-token "$LEIKWAN_OPERATOR_TOKEN" \
  --strict-auth
```

`--token` sets the Agent token. `--operator-token` sets the Operator token. `--strict-auth` requires the Operator token for every non-health Web API request. Without `--strict-auth`, readonly GET APIs can be viewed without an Operator token, but all mutating operator APIs still require it.

If `LEIKWAN_OPERATOR_TOKEN` is not configured, the Controller can still start. Mutating operator APIs return `403 operator token required`.

## Auth Status

```text
GET /api/v1/auth/status
```

The response includes:

- `operator_auth_configured`
- `strict_auth`
- `agent_auth_configured`
- `version`

When `--strict-auth=true`, `/api/v1/auth/status` also requires the Operator token. `/api/v1/health` remains unauthenticated.

## Audit Identity

The Controller never stores full tokens in events, task timelines, Plan audit fields, or logs. Operator identity is stored as a short fingerprint such as:

```text
operator:abcd1234
```

This allows audit trails to show that an operator performed an action without exposing the token.

## Redaction

Panel redacts these fields in raw JSON, task output, events, timeline data, logs and frontend views:

- `token`
- `secret`
- `password`
- `privateKey`
- `network_secret`
- `custom_url`
- `custom_cmd`
- `Authorization`
- `operator_token`
- `controller_token`

## Safety Boundary

Operator Auth does not enable write automation in 2.1.0. The Panel still does not create write tasks, execute arbitrary commands, restart relay, create snapshots, run rollback, or modify nftables, systemd, EasyTier, DDNS, entries, forwards or PBR.
