# Development

## Controller

```bash
cd panel/controller
gofmt -w .
go test ./... -v -count=1 -timeout=30s
```

## Agent

```bash
cd panel/agent
gofmt -w .
go test ./... -v -count=1 -timeout=30s
```

## Web

```bash
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build
```

## Release

```bash
bash -n panel/scripts/*.sh
bash panel/scripts/build-release.sh
```
