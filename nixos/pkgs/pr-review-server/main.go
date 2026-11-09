// pr-review-server serves pr-review-doc pages and proxies their GitHub review
// threads through the gh CLI, pushing cached snapshots to pages over SSE.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"sync"
	"time"
)

const pollInterval = 30 * time.Second

var segment = regexp.MustCompile(`^[A-Za-z0-9_.-]+$`)

type server struct {
	pagesDir     string
	cacheDir     string
	allowedHosts map[string]bool

	mu  sync.Mutex
	prs map[string]*pullRequest
}

type pullRequest struct {
	owner, repo string
	number      int

	// fetchMu serialises GitHub fetches; the server mutex guards the rest.
	fetchMu  sync.Mutex
	snapshot []byte
	subs     map[chan []byte]struct{}
}

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatal(err)
	}
	addr := flag.String("addr", "127.0.0.1:7457", "listen address")
	pagesDir := flag.String("pages", filepath.Join(home, ".cache", "pr-review"), "directory holding built review pages")
	cacheDir := flag.String("cache", filepath.Join(home, ".cache", "pr-review-server"), "directory for cached thread snapshots")
	flag.Parse()

	_, port, err := net.SplitHostPort(*addr)
	if err != nil {
		log.Fatal(err)
	}
	s := &server{
		pagesDir: *pagesDir,
		cacheDir: *cacheDir,
		// Checking Host blocks DNS rebinding from other sites.
		allowedHosts: map[string]bool{"127.0.0.1:" + port: true, "localhost:" + port: true},
		prs:          map[string]*pullRequest{},
	}
	go s.poll()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /pr/{owner}/{repo}/{number}", s.page)
	mux.HandleFunc("GET /api/pr/{owner}/{repo}/{number}/events", s.events)
	mux.HandleFunc("POST /api/pr/{owner}/{repo}/{number}/threads", s.addThread)
	mux.HandleFunc("POST /api/pr/{owner}/{repo}/{number}/threads/{thread}/replies", s.addReply)
	mux.HandleFunc("POST /api/pr/{owner}/{repo}/{number}/threads/{thread}/resolve", s.resolveThread)
	mux.HandleFunc("DELETE /api/pr/{owner}/{repo}/{number}/comments/{comment}", s.deleteComment)
	mux.HandleFunc("POST /api/pr/{owner}/{repo}/{number}/review", s.submitReview)

	log.Printf("listening on http://%s", *addr)
	log.Fatal(http.ListenAndServe(*addr, s.guard(mux)))
}

// guard only lets same-origin pages served by this process reach the API.
func (s *server) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.allowedHosts[r.Host] {
			http.Error(w, "forbidden host", http.StatusForbidden)
			return
		}
		if r.Method != http.MethodGet {
			if r.Header.Get("Origin") != "http://"+r.Host || r.Header.Get("Content-Type") != "application/json" {
				http.Error(w, "forbidden origin", http.StatusForbidden)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) page(w http.ResponseWriter, r *http.Request) {
	owner, repo, number, ok := prParams(w, r)
	if !ok {
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	http.ServeFile(w, r, filepath.Join(s.pagesDir, owner, repo, strconv.Itoa(number), "index.html"))
}

func prParams(w http.ResponseWriter, r *http.Request) (string, string, int, bool) {
	owner, repo := r.PathValue("owner"), r.PathValue("repo")
	number, err := strconv.Atoi(r.PathValue("number"))
	if !segment.MatchString(owner) || !segment.MatchString(repo) || owner == ".." || repo == ".." || err != nil || number <= 0 {
		http.Error(w, "bad pull request", http.StatusBadRequest)
		return "", "", 0, false
	}
	return owner, repo, number, true
}

func (s *server) pr(w http.ResponseWriter, r *http.Request) (*pullRequest, bool) {
	owner, repo, number, ok := prParams(w, r)
	if !ok {
		return nil, false
	}
	key := fmt.Sprintf("%s/%s#%d", owner, repo, number)
	s.mu.Lock()
	defer s.mu.Unlock()
	p := s.prs[key]
	if p == nil {
		p = &pullRequest{owner: owner, repo: repo, number: number, subs: map[chan []byte]struct{}{}}
		p.snapshot, _ = os.ReadFile(s.cachePath(p))
		s.prs[key] = p
	}
	return p, true
}

func (s *server) cachePath(p *pullRequest) string {
	return filepath.Join(s.cacheDir, p.owner, p.repo, strconv.Itoa(p.number)+".json")
}

func (s *server) events(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pr(w, r)
	if !ok {
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-store")

	ch := make(chan []byte, 1)
	s.mu.Lock()
	p.subs[ch] = struct{}{}
	if p.snapshot != nil {
		ch <- frame("snapshot", p.snapshot)
	}
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(p.subs, ch)
		s.mu.Unlock()
	}()
	go s.refresh(p)

	fmt.Fprint(w, ": connected\n\n")
	flusher.Flush()
	for {
		select {
		case <-r.Context().Done():
			return
		case msg := <-ch:
			w.Write(msg)
			flusher.Flush()
		}
	}
}

func frame(event string, data []byte) []byte {
	return fmt.Appendf(nil, "event: %s\ndata: %s\n\n", event, data)
}

// broadcast replaces any undelivered message, as only the latest state matters.
func (s *server) broadcast(p *pullRequest, msg []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for ch := range p.subs {
		select {
		case <-ch:
		default:
		}
		ch <- msg
	}
}

func (s *server) poll() {
	for range time.Tick(pollInterval) {
		s.mu.Lock()
		var watched []*pullRequest
		for _, p := range s.prs {
			if len(p.subs) > 0 {
				watched = append(watched, p)
			}
		}
		s.mu.Unlock()
		for _, p := range watched {
			go s.refresh(p)
		}
	}
}

const snapshotQuery = `query($owner: String!, $repo: String!, $number: Int!, $after: String) {
  viewer { login }
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      id
      headRefOid
      reviews(states: PENDING, first: 1) { nodes { id } }
      reviewThreads(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path diffSide line startLine originalLine originalStartLine
          comments(first: 100) {
            nodes { id bodyHTML createdAt url state author { login } }
          }
        }
      }
    }
  }
}`

type snapshotPage struct {
	Viewer struct {
		Login string `json:"login"`
	} `json:"viewer"`
	Repository struct {
		PullRequest struct {
			ID         string `json:"id"`
			HeadRefOid string `json:"headRefOid"`
			Reviews    struct {
				Nodes []struct {
					ID string `json:"id"`
				} `json:"nodes"`
			} `json:"reviews"`
			ReviewThreads struct {
				PageInfo struct {
					HasNextPage bool   `json:"hasNextPage"`
					EndCursor   string `json:"endCursor"`
				} `json:"pageInfo"`
				Nodes []json.RawMessage `json:"nodes"`
			} `json:"reviewThreads"`
		} `json:"pullRequest"`
	} `json:"repository"`
}

type snapshot struct {
	Viewer          string            `json:"viewer"`
	HeadOid         string            `json:"headOid"`
	PendingReviewID string            `json:"pendingReviewId"`
	Threads         []json.RawMessage `json:"threads"`
}

func (s *server) refresh(p *pullRequest) {
	p.fetchMu.Lock()
	defer p.fetchMu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()

	snap := snapshot{Threads: []json.RawMessage{}}
	vars := map[string]any{"owner": p.owner, "repo": p.repo, "number": p.number}
	for {
		var page snapshotPage
		if err := graphql(ctx, snapshotQuery, vars, &page); err != nil {
			log.Printf("refresh %s/%s#%d: %v", p.owner, p.repo, p.number, err)
			// Not "error", which EventSource reserves for connection errors.
			s.broadcast(p, frame("failure", must(json.Marshal(err.Error()))))
			return
		}
		pr := page.Repository.PullRequest
		snap.Viewer = page.Viewer.Login
		snap.HeadOid = pr.HeadRefOid
		if len(pr.Reviews.Nodes) > 0 {
			snap.PendingReviewID = pr.Reviews.Nodes[0].ID
		}
		snap.Threads = append(snap.Threads, pr.ReviewThreads.Nodes...)
		if !pr.ReviewThreads.PageInfo.HasNextPage {
			break
		}
		vars["after"] = pr.ReviewThreads.PageInfo.EndCursor
	}

	data := must(json.Marshal(snap))
	s.mu.Lock()
	changed := !bytes.Equal(p.snapshot, data)
	p.snapshot = data
	s.mu.Unlock()
	if !changed {
		return
	}
	path := s.cachePath(p)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err == nil {
		os.WriteFile(path, data, 0o600)
	}
	s.broadcast(p, frame("snapshot", data))
}

func graphql(ctx context.Context, query string, vars map[string]any, out any) error {
	cmd := exec.CommandContext(ctx, "gh", "api", "graphql", "--input", "-")
	cmd.Stdin = bytes.NewReader(must(json.Marshal(map[string]any{"query": query, "variables": vars})))
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	stdout, err := cmd.Output()
	var res struct {
		Data   json.RawMessage `json:"data"`
		Errors []struct {
			Message string `json:"message"`
		} `json:"errors"`
	}
	json.Unmarshal(stdout, &res)
	if len(res.Errors) > 0 {
		return errors.New(res.Errors[0].Message)
	}
	if err != nil {
		return fmt.Errorf("%w: %s", err, bytes.TrimSpace(stderr.Bytes()))
	}
	return json.Unmarshal(res.Data, out)
}

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

// pendingReview returns the viewer's pending review, creating one on the
// commit the page was built from.
func pendingReview(ctx context.Context, p *pullRequest, commitOid string) (string, error) {
	var res struct {
		Repository struct {
			PullRequest struct {
				ID      string `json:"id"`
				Reviews struct {
					Nodes []struct {
						ID string `json:"id"`
					} `json:"nodes"`
				} `json:"reviews"`
			} `json:"pullRequest"`
		} `json:"repository"`
	}
	err := graphql(ctx, `query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) { id reviews(states: PENDING, first: 1) { nodes { id } } }
  }
}`, map[string]any{"owner": p.owner, "repo": p.repo, "number": p.number}, &res)
	if err != nil {
		return "", err
	}
	pr := res.Repository.PullRequest
	if len(pr.Reviews.Nodes) > 0 {
		return pr.Reviews.Nodes[0].ID, nil
	}
	var created struct {
		AddPullRequestReview struct {
			PullRequestReview struct {
				ID string `json:"id"`
			} `json:"pullRequestReview"`
		} `json:"addPullRequestReview"`
	}
	err = graphql(ctx, `mutation($pullRequestId: ID!, $commitOID: GitObjectID) {
  addPullRequestReview(input: {pullRequestId: $pullRequestId, commitOID: $commitOID}) { pullRequestReview { id } }
}`, map[string]any{"pullRequestId": pr.ID, "commitOID": commitOid}, &created)
	return created.AddPullRequestReview.PullRequestReview.ID, err
}

// mutate decodes the request body, runs fn, then pushes a fresh snapshot to
// every open page before answering.
func mutate[T any](s *server, w http.ResponseWriter, r *http.Request, fn func(context.Context, *pullRequest, T) error) {
	p, ok := s.pr(w, r)
	if !ok {
		return
	}
	var body T
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := fn(r.Context(), p, body); err != nil {
		log.Printf("%s %s: %v", r.Method, r.URL.Path, err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	s.refresh(p)
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) addThread(w http.ResponseWriter, r *http.Request) {
	mutate(s, w, r, func(ctx context.Context, p *pullRequest, in struct {
		CommitOid string  `json:"commitOid"`
		Path      string  `json:"path"`
		Line      int     `json:"line"`
		Side      string  `json:"side"`
		StartLine *int    `json:"startLine"`
		StartSide *string `json:"startSide"`
		Body      string  `json:"body"`
	}) error {
		reviewID, err := pendingReview(ctx, p, in.CommitOid)
		if err != nil {
			return err
		}
		return graphql(ctx, `mutation($pullRequestReviewId: ID!, $path: String!, $line: Int!, $side: DiffSide!, $startLine: Int, $startSide: DiffSide, $body: String!) {
  addPullRequestReviewThread(input: {pullRequestReviewId: $pullRequestReviewId, path: $path, line: $line, side: $side, startLine: $startLine, startSide: $startSide, body: $body}) { thread { id } }
}`, map[string]any{
			"pullRequestReviewId": reviewID, "path": in.Path, "line": in.Line, "side": in.Side,
			"startLine": in.StartLine, "startSide": in.StartSide, "body": in.Body,
		}, &struct{}{})
	})
}

func (s *server) addReply(w http.ResponseWriter, r *http.Request) {
	threadID := r.PathValue("thread")
	mutate(s, w, r, func(ctx context.Context, p *pullRequest, in struct {
		CommitOid string `json:"commitOid"`
		Body      string `json:"body"`
	}) error {
		reviewID, err := pendingReview(ctx, p, in.CommitOid)
		if err != nil {
			return err
		}
		return graphql(ctx, `mutation($pullRequestReviewId: ID!, $threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewId: $pullRequestReviewId, pullRequestReviewThreadId: $threadId, body: $body}) { comment { id } }
}`, map[string]any{"pullRequestReviewId": reviewID, "threadId": threadID, "body": in.Body}, &struct{}{})
	})
}

func (s *server) resolveThread(w http.ResponseWriter, r *http.Request) {
	threadID := r.PathValue("thread")
	mutate(s, w, r, func(ctx context.Context, p *pullRequest, in struct {
		Resolved bool `json:"resolved"`
	}) error {
		mutation := "unresolveReviewThread"
		if in.Resolved {
			mutation = "resolveReviewThread"
		}
		return graphql(ctx, `mutation($threadId: ID!) { `+mutation+`(input: {threadId: $threadId}) { thread { id } } }`,
			map[string]any{"threadId": threadID}, &struct{}{})
	})
}

func (s *server) deleteComment(w http.ResponseWriter, r *http.Request) {
	commentID := r.PathValue("comment")
	mutate(s, w, r, func(ctx context.Context, p *pullRequest, _ struct{}) error {
		return graphql(ctx, `mutation($id: ID!) { deletePullRequestReviewComment(input: {id: $id}) { pullRequestReview { id } } }`,
			map[string]any{"id": commentID}, &struct{}{})
	})
}

func (s *server) submitReview(w http.ResponseWriter, r *http.Request) {
	mutate(s, w, r, func(ctx context.Context, p *pullRequest, in struct {
		CommitOid string `json:"commitOid"`
		Event     string `json:"event"`
		Body      string `json:"body"`
	}) error {
		reviewID, err := pendingReview(ctx, p, in.CommitOid)
		if err != nil {
			return err
		}
		return graphql(ctx, `mutation($pullRequestReviewId: ID!, $event: PullRequestReviewEvent!, $body: String) {
  submitPullRequestReview(input: {pullRequestReviewId: $pullRequestReviewId, event: $event, body: $body}) { pullRequestReview { id } }
}`, map[string]any{"pullRequestReviewId": reviewID, "event": in.Event, "body": in.Body}, &struct{}{})
	})
}
