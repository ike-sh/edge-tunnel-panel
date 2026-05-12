# Release

Build release archives from the repository root:

```bash
VERSION=0.1.0 bash panel/scripts/build-release.sh
```

Generated files:

- `panel/dist/edge-tunnel-panel-0.1.0-linux-amd64.tar.gz`
- `panel/dist/edge-tunnel-panel-0.1.0-linux-arm64.tar.gz`
- `panel/dist/SHA256SUMS`

Each archive contains:

- `edge-tunnel-controller`
- `edge-tunnel-agent`
- `web/`
- `docs/`
- `examples/`
- `scripts/`
- `VERSION`
