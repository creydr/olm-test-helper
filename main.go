package main

import (
	"fmt"
	"net/http"
	"os"
)

var (
	version string = "plain-build"
	name    string = "World"
)

func hello(w http.ResponseWriter, req *http.Request) {
	fmt.Fprintf(w, "Hello %s\n", name)
}

func main() {
	if v, ok := os.LookupEnv("NAME"); ok {
		name = v
	}
	fmt.Printf("Running version %s\n", version)
	fmt.Printf("Running with name=%s\n", name)

	http.HandleFunc("/", hello)

	host := "0.0.0.0"
	port := "8080"

	if res, ok := os.LookupEnv("HOST"); ok {
		host = res
	}

	if res, ok := os.LookupEnv("PORT"); ok {
		port = res
	}

	fmt.Printf("Starting server on %s:%s...\n", host, port)

	http.ListenAndServe(fmt.Sprintf("%s:%s", host, port), nil)
}
