package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller"
)

const (
	defaultOperatorToken = "edge-operator-token"
	defaultAgentToken    = "edge-agent-token"
)

var version = "v0.3.1"

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	showVersion := flag.Bool("version", false, "print version")
	flag.Parse()
	if *showVersion {
		fmt.Printf("edge-tunnel-controller %s\n", version)
		return
	}
	listen := getenv("EDGE_LISTEN", "0.0.0.0:18080")
	dataDir := getenv("EDGE_DATA_DIR", "/var/lib/edge-tunnel/controller")
	webDir := getenv("EDGE_WEB_DIR", filepath.Join(dataDir, "web"))
	operatorToken := getenv("EDGE_OPERATOR_TOKEN", defaultOperatorToken)
	agentToken := getenv("EDGE_CONTROLLER_TOKEN", defaultAgentToken)
	strict := getenv("EDGE_STRICT_AUTH", "true") == "true"
	if strict && (operatorToken == defaultOperatorToken || agentToken == defaultAgentToken) {
		log.Fatal("EDGE_STRICT_AUTH=true 时必须设置自定义 EDGE_OPERATOR_TOKEN 与 EDGE_CONTROLLER_TOKEN；生产请使用 quick-install.sh 安装")
	}
	store, err := controller.OpenStore(filepath.Join(dataDir, "store.json"))
	if err != nil {
		log.Fatal(err)
	}
	h := controller.NewServer(store, agentToken, operatorToken, strict, webDir)
	log.Printf("edge-tunnel-controller listening on %s", listen)
	log.Fatal(http.ListenAndServe(listen, h))
}
