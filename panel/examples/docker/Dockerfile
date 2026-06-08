# Edge Tunnel Panel Controller 镜像（从 GitHub Release 构建）
# 构建：docker build -f panel/examples/docker/Dockerfile --build-arg VERSION=v0.3.1 -t edge-tunnel-panel:local panel/examples/docker
ARG VERSION=latest
FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl tar \
  && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
RUN set -eux; \
  case "${TARGETARCH:-amd64}" in \
    amd64) ARCH=amd64 ;; \
    arm64) ARCH=arm64 ;; \
    *) echo "unsupported arch: ${TARGETARCH}"; exit 1 ;; \
  esac; \
  if [ "$VERSION" = "latest" ]; then \
    VERSION="$(curl -fsSL https://api.github.com/repos/ike-sh/edge-tunnel-panel/releases/latest | sed -n 's/.*\"tag_name\": \"\\([^\"]*\\)\".*/\\1/p' | head -n1)"; \
  fi; \
  ASSET="edge-tunnel-panel-${VERSION}-linux-${ARCH}.tar.gz"; \
  URL="https://github.com/ike-sh/edge-tunnel-panel/releases/download/${VERSION}/${ASSET}"; \
  mkdir -p /opt/edge-tunnel-panel; \
  curl -fsSL "$URL" | tar -xz -C /opt/edge-tunnel-panel; \
  install -m 0755 /opt/edge-tunnel-panel/edge-tunnel-controller /usr/local/bin/edge-tunnel-controller

ENV EDGE_LISTEN=0.0.0.0:18080 \
    EDGE_DATA_DIR=/var/lib/edge-tunnel/controller \
    EDGE_WEB_DIR=/opt/edge-tunnel-panel/web \
    EDGE_STRICT_AUTH=true \
    EDGE_FORCE_HTTPS=1

RUN mkdir -p /var/lib/edge-tunnel/controller
VOLUME ["/var/lib/edge-tunnel/controller"]
EXPOSE 18080
CMD ["edge-tunnel-controller"]
