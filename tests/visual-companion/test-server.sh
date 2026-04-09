#!/usr/bin/env bash
# test-server.sh
# Tests for skills/visual-companion/server.py covering security, validation,
# SSE, and cleanup behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVER="$REPO_ROOT/skills/visual-companion/server.py"

PASS=0
FAIL=0
SERVER_PID=""

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$SERVE_DIR"
}
trap cleanup EXIT

# --- Setup ---

SERVE_DIR=$(mktemp -d /tmp/vc-test-XXXXXX)
echo "<h1>test</h1>" > "$SERVE_DIR/index.html"

python3 "$SERVER" --dir "$SERVE_DIR" &
SERVER_PID=$!

# Wait for server to start (max 10 seconds)
for i in $(seq 1 20); do
    if [ -f "$SERVE_DIR/.vc-meta/server-info.json" ]; then
        break
    fi
    sleep 0.5
done

# Read port from .vc-meta/server-info.json
INFO_FILE="$SERVE_DIR/.vc-meta/server-info.json"
if [ ! -f "$INFO_FILE" ]; then
  echo "FATAL: server-info.json not created at $INFO_FILE"
  exit 1
fi
PORT=$(python3 -c "import json; print(json.load(open('$INFO_FILE'))['port'])")
BASE="http://127.0.0.1:$PORT"

echo "Server running on port $PORT (PID $SERVER_PID)"
echo ""

# --- Test 1: Path traversal returns 403 ---

echo "=== Security ==="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "$BASE/../../etc/passwd")
[ "$STATUS" = "403" ] && pass "path traversal blocked (403)" || fail "path traversal returned $STATUS, expected 403"

# --- Test 2: Normal file serving returns 200 ---

echo ""
echo "=== File Serving ==="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/index.html")
[ "$STATUS" = "200" ] && pass "normal file serving (200)" || fail "normal serving returned $STATUS, expected 200"

BODY=$(curl -s "$BASE/index.html")
echo "$BODY" | grep -q "<h1>test</h1>" && pass "response contains original content" || fail "original content missing"
echo "$BODY" | grep -q "EventSource" && pass "client JS injected" || fail "client JS not injected"

# --- Test 2b: Full HTML document serves with JS injection before </body> ---

echo "<html><head></head><body><h1>full doc</h1></body></html>" > "$SERVE_DIR/full.html"
FULL_BODY=$(curl -s "$BASE/full.html")
echo "$FULL_BODY" | grep -q "<h1>full doc</h1>" && pass "full doc contains original content" || fail "full doc original content missing"
echo "$FULL_BODY" | grep -q "new EventSource" && pass "full doc has JS injected" || fail "full doc JS not injected"
# Verify JS appears before </body> by checking the order in output
JS_LINE=$(echo "$FULL_BODY" | grep -n "new EventSource" | head -1 | cut -d: -f1)
BODY_LINE=$(echo "$FULL_BODY" | grep -n "</body>" | head -1 | cut -d: -f1)
[ -n "$JS_LINE" ] && [ -n "$BODY_LINE" ] && [ "$JS_LINE" -lt "$BODY_LINE" ] && pass "full doc JS injected before </body>" || fail "full doc JS not before </body>"

# --- Test 3: .vc-meta not accessible via GET ---

STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/.vc-meta/server-info.json")
[ "$STATUS" = "404" ] && pass ".vc-meta blocked (404)" || fail ".vc-meta returned $STATUS, expected 404"

# --- Test 3b: DELETE before events exist returns 204 ---

echo ""
echo "=== DELETE ==="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/events")
[ "$STATUS" = "204" ] && pass "DELETE before events exist (204)" || fail "DELETE pre-events returned $STATUS, expected 204"

# --- Test 4: Oversized POST returns 413 ---

echo ""
echo "=== POST Validation ==="
LARGE_BODY=$(python3 -c "print('x' * 70000)")
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST -d "$LARGE_BODY" "$BASE/event")
[ "$STATUS" = "413" ] && pass "POST size limit (413)" || fail "oversized POST returned $STATUS, expected 413"

# --- Test 5: Empty POST returns 204 ---

STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Length: 0" "$BASE/event")
[ "$STATUS" = "204" ] && pass "empty POST body (204)" || fail "empty POST returned $STATUS, expected 204"

# Verify no blank line written to events.jsonl
EVENTS_FILE="$SERVE_DIR/.vc-meta/events.jsonl"
if [ -f "$EVENTS_FILE" ]; then
  LINES=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
  [ "$LINES" = "0" ] && pass "no blank line in events.jsonl" || fail "events.jsonl has $LINES lines after empty POST"
else
  pass "no blank line in events.jsonl (file not created)"
fi

# --- Test 5b: Valid POST persists event ---

EVENT='{"type":"choice","choice":"A","text":"Option A"}'
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: application/json" -d "$EVENT" "$BASE/event")
[ "$STATUS" = "204" ] && pass "valid POST accepted (204)" || fail "valid POST returned $STATUS, expected 204"
grep -q '"choice":"A"' "$SERVE_DIR/.vc-meta/events.jsonl" && pass "event persisted to events.jsonl" || fail "event not found in events.jsonl"

# --- Test 5b2: POST invalid JSON returns 400 ---

INVALID_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -d 'not-valid-json' "$BASE/event")
[ "$INVALID_RESPONSE" = "400" ] && pass "POST invalid JSON rejected (400)" || fail "POST invalid JSON returned $INVALID_RESPONSE, expected 400"

# --- Test 5c: DELETE after events exist truncates file ---

STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/events")
[ "$STATUS" = "204" ] && pass "DELETE clears events (204)" || fail "DELETE returned $STATUS, expected 204"
[ ! -s "$SERVE_DIR/.vc-meta/events.jsonl" ] && pass "events.jsonl truncated" || fail "events.jsonl not empty after DELETE"

# --- Test 6: Invalid Content-Length returns 400 ---

STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Length: abc" -H "Transfer-Encoding: identity" --data-raw "" "$BASE/event")
[ "$STATUS" = "400" ] && pass "invalid content-length (400)" || fail "invalid CL returned $STATUS, expected 400"

# --- Test 7a: GET returns 413 for files exceeding 10MB ---

echo ""
echo "=== File Size Limit ==="
dd if=/dev/zero of="$SERVE_DIR/huge.bin" bs=1024 count=10241 2>/dev/null
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/huge.bin")
[ "$STATUS" = "413" ] && pass "GET huge file returns 413" || fail "GET huge file returned $STATUS, expected 413"
rm -f "$SERVE_DIR/huge.bin"

# --- Test 7b: events.jsonl truncates to 100 lines when exceeding 1MB ---

echo ""
echo "=== Events Truncation ==="
META_DIR="$SERVE_DIR/.vc-meta"
mkdir -p "$META_DIR"
LARGE_VALUE=$(python3 -c "print('x' * 8000)")
for i in $(seq 1 150); do
    echo "{\"type\":\"pad\",\"data\":\"$LARGE_VALUE\"}" >> "$META_DIR/events.jsonl"
done
# POST one more event to trigger truncation
curl -s -X POST -H "Content-Type: application/json" -d '{"type":"trigger"}' "$BASE/event" > /dev/null
LINE_COUNT=$(wc -l < "$META_DIR/events.jsonl" | tr -d ' ')
test "$LINE_COUNT" -le 101
[ "$?" = "0" ] && pass "events.jsonl truncated to <=101 lines after exceeding 1MB (got $LINE_COUNT)" || fail "events.jsonl has $LINE_COUNT lines, expected <=101"
rm -f "$META_DIR/events.jsonl"

# --- Test 7c: SSE endpoint returns event-stream ---

echo ""
echo "=== SSE ==="
HEADERS=$(curl -sD - -o /dev/null --max-time 2 "$BASE/sse" 2>/dev/null || true)
echo "$HEADERS" | grep -qi "text/event-stream" && pass "SSE content type" || fail "SSE content type not found in: $HEADERS"

# --- Test 8: Cleanup on shutdown ---

echo ""
echo "=== Cleanup ==="
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""
sleep 1
[ ! -f "$INFO_FILE" ] && pass "cleanup on shutdown (server-info.json removed)" || fail "server-info.json not cleaned up"

# --- Results ---

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
