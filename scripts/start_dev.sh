#!/bin/bash
# Start Roxy-WI in development mode from source
# This script initializes the environment and starts the Flask development server

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
VENV_DIR="${PROJECT_ROOT}/venv"
LOG_DIR="${PROJECT_ROOT}/logs"
LIB_DIR="${PROJECT_ROOT}/.roxy-wi-dev/lib"
CONFIG_DIR="${PROJECT_ROOT}/.roxy-wi-dev/etc"
CONFIG_FILE="${CONFIG_DIR}/roxy-wi.cfg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Roxy-WI Development Server Starter${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    exit 1
fi

echo "Python version: $(python3 --version)"
echo ""

# Create directories if they don't exist
echo "Creating necessary directories..."
mkdir -p "$LOG_DIR"
mkdir -p "$LIB_DIR"/{configs/hap_config,configs/kp_config,configs/nginx_config,configs/apache_config}
mkdir -p "$CONFIG_DIR"

# Create or update configuration file
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating development configuration file at $CONFIG_FILE"
    cat > "$CONFIG_FILE" << 'EOF'
[main]
# Development paths
fullpath = PWD_PLACEHOLDER
log_path = LOG_DIR_PLACEHOLDER
lib_path = LIB_DIR_PLACEHOLDER
# Generate a Fernet key with: python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
secret_phrase = CHANGE_ME

[configs]
# Folders for configs
haproxy_save_configs_dir = LIB_DIR_PLACEHOLDER/configs/hap_config/
keepalived_save_configs_dir = LIB_DIR_PLACEHOLDER/configs/kp_config/
nginx_save_configs_dir = LIB_DIR_PLACEHOLDER/configs/nginx_config/
apache_save_configs_dir = LIB_DIR_PLACEHOLDER/configs/apache_config/

[mysql]
# By default Sqlite DB is used in development
enable = 0
mysql_user = roxy-wi
mysql_password = roxy-wi
mysql_db = roxywi
mysql_host = 127.0.0.1
mysql_port = 3306
EOF

    # Replace placeholders with actual paths
    sed -i "s|PWD_PLACEHOLDER|$PROJECT_ROOT|g" "$CONFIG_FILE"
    sed -i "s|LOG_DIR_PLACEHOLDER|$LOG_DIR|g" "$CONFIG_FILE"
    sed -i "s|LIB_DIR_PLACEHOLDER|$LIB_DIR|g" "$CONFIG_FILE"
else
    echo -e "${YELLOW}Configuration file already exists: $CONFIG_FILE${NC}"
fi

echo ""

# Create or activate virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
else
    echo "Using existing virtual environment at $VENV_DIR"
fi

echo ""
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip setuptools wheel > /dev/null 2>&1

# Install dependencies
echo "Installing dependencies from requirements.txt..."
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
    pip install -r "$PROJECT_ROOT/requirements.txt" > /dev/null 2>&1 || {
        echo -e "${YELLOW}Warning: Some dependencies failed to install${NC}"
        echo "Try installing manually with: pip install -r requirements.txt"
    }
else
    echo -e "${RED}Error: requirements.txt not found${NC}"
    exit 1
fi

# Install dev dependencies if they exist
if [ -f "$PROJECT_ROOT/requirements-dev.txt" ]; then
    echo "Installing development dependencies..."
    pip install -r "$PROJECT_ROOT/requirements-dev.txt" > /dev/null 2>&1
fi

echo ""

# Initialize database
echo "Initializing database..."
cd "$PROJECT_ROOT"
export ROXYWI_CONFIG="$CONFIG_FILE"
python3 app/create_db.py > /dev/null 2>&1 || {
    echo -e "${YELLOW}Warning: Database initialization may have issues${NC}"
}

# Apply migrations
echo "Applying database migrations..."
python3 app/migrate.py migrate > /dev/null 2>&1 || {
    echo -e "${YELLOW}Warning: Database migration may have issues${NC}"
}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Starting Roxy-WI Development Server${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Environment:"
echo "  Python: $(python3 --version)"
echo "  Project: $PROJECT_ROOT"
echo "  Logs: $LOG_DIR"
echo "  Database: $LIB_DIR"
echo "  Config: $CONFIG_FILE"
echo ""
echo "Server will start at http://localhost:5000"
echo "Admin login: admin/admin (default credentials)"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo ""

# Export configuration
export ROXYWI_CONFIG="$CONFIG_FILE"
export ROXYWI_TESTING=0

# Start Flask development server
cd "$PROJECT_ROOT"
python3 -c "from app import app; app.run(debug=True, host='0.0.0.0', port=5000)"
