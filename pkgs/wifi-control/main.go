package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		slog.Error(err.Error())
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: wifi-control serve --config FILE [options] | status --router ID | set --router ID on|off | lock --router ID on|off | scheduled-set on|off")
	}
	if args[0] == "status" || args[0] == "set" || args[0] == "lock" || args[0] == "scheduled-set" {
		return command(args[0], args[1:])
	}
	if args[0] != "serve" {
		return errors.New("unknown command")
	}
	flags := flag.NewFlagSet("serve", flag.ContinueOnError)
	listen := flags.String("listen", "127.0.0.1:8790", "HTTP listen address")
	configFile := flags.String("config", "", "JSON router definitions and credential references")
	stateFile := flags.String("state-file", "/var/lib/wifi-control/locks.json", "internal persistent schedule lock state")
	publicURL := flags.String("public-url", "", "public origin of the control page")
	timezone := flags.String("timezone", "Europe/Madrid", "schedule display timezone")
	on := flags.String("on", "07:00", "daily on time, matching the external timer")
	off := flags.String("off", "23:00", "daily off time, matching the external timer")
	if err := flags.Parse(args[1:]); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected serve arguments")
	}
	schedule, err := newSchedule(*timezone, *on, *off)
	if err != nil {
		return err
	}
	config, err := loadConfig(*configFile)
	if err != nil {
		return err
	}
	locks, err := loadLocks(*stateFile)
	if err != nil {
		return err
	}
	app := &application{fleet: newFleet(config, locks), schedule: schedule, publicURL: strings.TrimRight(*publicURL, "/")}
	server := &http.Server{
		Addr: *listen, Handler: app.handler(), ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout: 10 * time.Second, WriteTimeout: 60 * time.Second, IdleTimeout: 30 * time.Second,
	}
	listener, err := net.Listen("tcp", *listen)
	if err != nil {
		return err
	}
	defer listener.Close()
	if socket := os.Getenv("NOTIFY_SOCKET"); socket != "" {
		connection, err := net.Dial("unixgram", socket)
		if err != nil {
			return fmt.Errorf("systemd readiness notification failed: %w", err)
		}
		_, err = connection.Write([]byte("READY=1"))
		_ = connection.Close()
		if err != nil {
			return fmt.Errorf("systemd readiness notification failed: %w", err)
		}
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	go func() {
		<-ctx.Done()
		shutdown, done := context.WithTimeout(context.Background(), 10*time.Second)
		defer done()
		_ = server.Shutdown(shutdown)
	}()
	slog.Info("Wi-Fi control listening", "address", *listen)
	if err := server.Serve(listener); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func command(action string, args []string) error {
	flags := flag.NewFlagSet(action, flag.ContinueOnError)
	server := flags.String("server", "http://127.0.0.1:8790", "control service URL")
	routerID := flags.String("router", "", "configured router ID")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if action != "scheduled-set" && !identifierPattern.MatchString(*routerID) {
		return errors.New("provide --router with a configured router ID")
	}
	if action == "scheduled-set" && *routerID != "" {
		return errors.New("scheduled-set applies to all unlocked routers")
	}
	method, path, body := http.MethodGet, "/api/routers/"+*routerID+"/status", ""
	if action != "status" {
		if flags.NArg() != 1 || (flags.Arg(0) != "on" && flags.Arg(0) != "off") {
			return errors.New("command requires on or off")
		}
		method, path = http.MethodPost, "/api/routers/"+*routerID+"/wifi"
		body = fmt.Sprintf(`{"enabled":%t}`, flags.Arg(0) == "on")
		if action == "scheduled-set" {
			path = "/api/schedule"
		} else if action == "lock" {
			path = "/api/routers/" + *routerID + "/lock"
			body = fmt.Sprintf(`{"locked":%t}`, flags.Arg(0) == "on")
		}
	} else if flags.NArg() != 0 {
		return errors.New("unexpected status arguments")
	}
	req, err := http.NewRequest(method, strings.TrimRight(*server, "/")+path, strings.NewReader(body))
	if err != nil {
		return err
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	client := &http.Client{Timeout: 65 * time.Second}
	response, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("control service request failed: %w", err)
	}
	defer response.Body.Close()
	var result json.RawMessage
	if err := json.NewDecoder(io.LimitReader(response.Body, 64<<10)).Decode(&result); err != nil {
		return err
	}
	fmt.Println(string(result))
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("control service returned HTTP %d; check wifi-control.service logs", response.StatusCode)
	}
	return nil
}
