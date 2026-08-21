#!/bin/bash
# Start Roxy-WI in production mode using Gunicorn
# This script starts the application with Gunicorn WSGI server

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
VENV_DIR="${PROJECT_ROOT}/venv"
LOG_DIR="/var/log/roxy-wi"
CONFIG_FILE="/etc/roxy-wi/roxy-wi.cfg"
PID_FILE="/var/run/roxy-wi/roxy-wi.pid"
SOCKET_FILE="/var/run/roxy-wi/roxy-wi.sock"
WORKERS=${ROXY_WI_WORKERS:-4}
THREADS=${ROXY_WI_THREADS:-2}
BIND_ADDRESS=${ROXY_WI_BIND:-"127.0.0.1:8000"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Roxy-WI Production Server Starter${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo -e "${YELLOW}Warning: Not running as root. May have permission issues.${NC}"
   # Adjust paths for non-root
   LOG_DIR="${PROJECT_ROOT}/.roxy-wi/log"
   PID_FILE="${PROJECT_ROOT}/.roxy-wi/roxy-wi.pid"
   SOCKET_FILE="${PROJECT_ROOT}/.roxy-wi/roxy-wi.sock"
fi

# Create directories if they don't exist
mkdir -p "$(dirname "$PID_FILE")" 2>/dev/null || true
mkdir -p "$(dirname "$SOCKET_FILE")" 2>/dev/null || true
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Check if configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Warning: Configuration file not found at $CONFIG_FILE${NC}"
    echo "Using default configuration from $PROJECT_ROOT/roxy-wi.cfg"
    CONFIG_FILE="$PROJECT_ROOT/roxy-wi.cfg"
fi

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    exit 1
fi

echo "Python version: $(python3 --version)"
echo ""

# Activate virtual environment if it exists
if [ -d "$VENV_DIR" ]; then
    echo "Activating virtual environment at $VENV_DIR..."
    source "$VENV_DIR/bin/activate"
else
    echo -e "${YELLOW}Virtual environment not found at $VENV_DIR${NC}"
    echo "Install dependencies with: pip install -r requirements.txt gunicorn"
fi

echo ""

# Check if Gunicorn is installed
if ! command -v gunicorn &> /dev/null; then
    echo -e "${RED}Error: Gunicorn is not installed${NC}"
    echo "Install it with: pip install gunicorn"
    exit 1
fi

echo "Gunicorn version: $(gunicorn --version 2>&1 | head -1)"
echo ""

# Apply pending migrations
echo "Applying database migrations..."
cd "$PROJECT_ROOT"
export ROXYWI_CONFIG="$CONFIG_FILE"
python3 app/migrate.py migrate 2>/dev/null || {
    echo -e "${YELLOW}Warning: Database migration completed with warnings${NC}"
}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Starting Roxy-WI with Gunicorn${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Config file: $CONFIG_FILE"
echo "  Workers: $WORKERS"
echo "  Threads per worker: $THREADS"
echo "  Bind address: $BIND_ADDRESS"
echo "  Socket: $SOCKET_FILE"
echo "  PID file: $PID_FILE"
echo "  Log directory: $LOG_DIR"
echo ""

# Start Gunicorn
cd "$PROJECT_ROOT"
export ROXYWI_CONFIG="$CONFIG_FILE"

gunicorn \
    --workers="$WORKERS" \
    --threads="$THREADS" \
    --bind="$BIND_ADDRESS" \
    --bind="unix:$SOCKET_FILE" \
    --pidfile="$PID_FILE" \
    --access-logfile="$LOG_DIR/access.log" \
    --error-logfile="$LOG_DIR/error.log" \
    --log-level=info \
    --timeout=120 \
    --graceful-timeout=30 \
    --keep-alive=5 \
    'app:app'
