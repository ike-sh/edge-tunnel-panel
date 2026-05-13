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

var version = "v0.1.5-test"

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
	operatorToken := getenv("EDGE_OPERATOR_TOKEN", "edge-operator-token")
	agentToken := getenv("EDGE_CONTROLLER_TOKEN", "edge-agent-token")
	strict := getenv("EDGE_STRICT_AUTH", "false") == "true"
	store, err := controller.OpenStore(filepath.Join(dataDir, "store.json"))
	if err != nil {
		log.Fatal(err)
	}
	h := controller.NewServer(store, agentToken, operatorToken, strict, webDir)
	log.Printf("edge-tunnel-controller listening on %s", listen)
	log.Fatal(http.ListenAndServe(listen, h))
}
