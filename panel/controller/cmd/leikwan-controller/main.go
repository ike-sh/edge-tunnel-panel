package main

import (
	"bufio"
	"flag"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/ike-sh/leikwan-toolkit/panel/controller/internal/controller"
)

func main() {
	listen := flag.String("listen", "0.0.0.0:18080", "HTTP listen address")
	dbPath := flag.String("db", "./data/controller.db", "SQLite database path")
	tokenFlag := flag.String("token", "", "controller bearer token")
	configPath := flag.String("config", "", "optional controller config path")
	flag.Parse()

	token := *tokenFlag
	if token == "" {
		token = os.Getenv("LEIKWAN_CONTROLLER_TOKEN")
	}
	if token == "" {
		token = tokenFromConfig(*configPath)
	}
	if token == "" {
		log.Print("[WARN] LEIKWAN_CONTROLLER_TOKEN is empty; set LEIKWAN_CONTROLLER_TOKEN manually or configure /etc/leikwan-panel/controller.yml before accepting agents")
	}

	store, err := controller.OpenStore(*dbPath)
	if err != nil {
		log.Fatalf("open store: %v", err)
	}
	defer store.Close()

	srv := controller.NewServer(store, token, log.Default())
	log.Printf("leikwan-controller %s listening on %s", controller.Version, *listen)
	if err := http.ListenAndServe(*listen, srv); err != nil {
		log.Fatal(err)
	}
}

func tokenFromConfig(path string) string {
	paths := []string{path}
	if path == "" {
		paths = []string{"./controller.yml", "/etc/leikwan-panel/controller.yml"}
	}
	for _, candidate := range paths {
		if candidate == "" {
			continue
		}
		token := readToken(candidate)
		if token != "" {
			return token
		}
	}
	return ""
}

func readToken(path string) string {
	file, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		if strings.TrimSpace(parts[0]) == "token" {
			return strings.Trim(strings.TrimSpace(parts[1]), `"'`)
		}
	}
	return ""
}
