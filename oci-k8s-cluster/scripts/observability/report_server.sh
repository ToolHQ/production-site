#!/usr/bin/env bash
# oci-k8s-cluster/scripts/observability/report_server.sh
# Managed helper for the TUI Inventory Report server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_ROOT="$SCRIPT_DIR/reports"
LATEST_LINK="$REPORT_ROOT/latest"
PORT=8000
HOST="0.0.0.0"
PID_FILE="$SCRIPT_DIR/.report_server.pid"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

status() {
    # Check systemd status first
    if systemctl --user is-active --quiet inventory-report 2>/dev/null; then
        echo -e "${GREEN}●${NC} Report server is running via systemd on http://$HOST:$PORT"
        return 0
    fi

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo -e "${GREEN}●${NC} Report server is running (PID: $PID) on http://$HOST:$PORT"
            return 0
        else
            echo -e "${RED}○${NC} Report server is not running (stale PID file found)"
            return 1
        fi
    else
        echo -e "${YELLOW}○${NC} Report server is not running"
        return 1
    fi
}

stop() {
    if systemctl --user is-active --quiet inventory-report 2>/dev/null; then
        echo -e "${YELLOW}Stopping systemd report server...${NC}"
        systemctl --user stop inventory-report.service
    fi

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo -e "${YELLOW}Stopping manual report server (PID: $PID)...${NC}"
        kill "$PID" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    
    # Final cleanup
    pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
}

start() {
    if [ ! -d "$LATEST_LINK" ]; then
        echo -e "${RED}Error: $LATEST_LINK directory not found. Generate a report first.${NC}"
        return 1
    fi

    if status >/dev/null 2>&1; then
        echo "Server is already running."
        return 0
    fi

    # Try starting via systemd if service file exists
    if systemctl --user list-unit-files inventory-report.service >/dev/null 2>&1; then
        echo -e "${GREEN}Starting report server via systemd...${NC}"
        systemctl --user start inventory-report.service
        sleep 1
        if systemctl --user is-active --quiet inventory-report; then
            echo -e "${GREEN}✅ Server started successfully via systemd.${NC}"
            return 0
        fi
    fi

    # Fallback to manual execution
    echo -e "${GREEN}Starting report server manually on http://$HOST:$PORT...${NC}"
    nohup python3 -m http.server $PORT --bind $HOST --directory "$LATEST_LINK" >/dev/null 2>&1 &
    NEW_PID=$!
    echo "$NEW_PID" > "$PID_FILE"
    
    sleep 1
    if ps -p "$NEW_PID" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Server started manually successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to start server manually.${NC}"
        rm -f "$PID_FILE"
        return 1
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
