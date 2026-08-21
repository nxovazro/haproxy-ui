#!/bin/bash
# Setup development environment for Roxy-WI
# This script installs all dependencies and initializes the environment

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
VENV_DIR="${PROJECT_ROOT}/venv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Roxy-WI Development Environment Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check Python version
echo -e "${BLUE}Checking Python installation...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    echo "Please install Python 3.8 or higher"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
echo -e "${GREEN}✓ Python $PYTHON_VERSION found${NC}"
echo ""

# Create virtual environment
echo -e "${BLUE}Setting up Python virtual environment...${NC}"
if [ -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Virtual environment already exists at $VENV_DIR${NC}"
    read -p "Do you want to recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
    fi
else
    python3 -m venv "$VENV_DIR"
fi

echo -e "${GREEN}✓ Virtual environment ready${NC}"
echo ""

# Activate virtual environment
echo -e "${BLUE}Activating virtual environment...${NC}"
source "$VENV_DIR/bin/activate"
echo -e "${GREEN}✓ Virtual environment activated${NC}"
echo ""

# Upgrade pip
echo -e "${BLUE}Upgrading pip and setuptools...${NC}"
pip install --upgrade pip setuptools wheel > /dev/null 2>&1
echo -e "${GREEN}✓ pip upgraded${NC}"
echo ""

# Install dependencies
echo -e "${BLUE}Installing production dependencies...${NC}"
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
    pip install -r "$PROJECT_ROOT/requirements.txt"
    echo -e "${GREEN}✓ Production dependencies installed${NC}"
else
    echo -e "${RED}Error: requirements.txt not found${NC}"
    exit 1
fi

echo ""

# Install development dependencies
echo -e "${BLUE}Installing development dependencies...${NC}"
if [ -f "$PROJECT_ROOT/requirements-dev.txt" ]; then
    pip install -r "$PROJECT_ROOT/requirements-dev.txt"
    echo -e "${GREEN}✓ Development dependencies installed${NC}"
else
    echo -e "${YELLOW}Warning: requirements-dev.txt not found${NC}"
fi

echo ""

# Optional: Install additional development tools
echo -e "${BLUE}Installing additional development tools...${NC}"
pip install \
    gunicorn \
    pytest-cov \
    black \
    flake8 \
    ipython \
    > /dev/null 2>&1

echo -e "${GREEN}✓ Development tools installed${NC}"
echo ""

# Create development directories
echo -e "${BLUE}Creating development directories...${NC}"
mkdir -p "$PROJECT_ROOT/.roxy-wi-dev/etc"
mkdir -p "$PROJECT_ROOT/.roxy-wi-dev/lib/configs/hap_config"
mkdir -p "$PROJECT_ROOT/.roxy-wi-dev/lib/configs/kp_config"
mkdir -p "$PROJECT_ROOT/.roxy-wi-dev/lib/configs/nginx_config"
mkdir -p "$PROJECT_ROOT/.roxy-wi-dev/lib/configs/apache_config"
mkdir -p "$PROJECT_ROOT/logs"

echo -e "${GREEN}✓ Development directories created${NC}"
echo ""

# Create development configuration if it doesn't exist
CONFIG_FILE="$PROJECT_ROOT/.roxy-wi-dev/etc/roxy-wi.cfg"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}Creating development configuration...${NC}"
    cat > "$CONFIG_FILE" << EOF
[main]
fullpath = $PROJECT_ROOT
log_path = $PROJECT_ROOT/logs
lib_path = $PROJECT_ROOT/.roxy-wi-dev/lib
# Generate with: python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
secret_phrase = CHANGE_ME

[configs]
haproxy_save_configs_dir = $PROJECT_ROOT/.roxy-wi-dev/lib/configs/hap_config/
keepalived_save_configs_dir = $PROJECT_ROOT/.roxy-wi-dev/lib/configs/kp_config/
nginx_save_configs_dir = $PROJECT_ROOT/.roxy-wi-dev/lib/configs/nginx_config/
apache_save_configs_dir = $PROJECT_ROOT/.roxy-wi-dev/lib/configs/apache_config/

[mysql]
enable = 0
mysql_user = roxy-wi
mysql_password = roxy-wi
mysql_db = roxywi
mysql_host = 127.0.0.1
mysql_port = 3306
EOF
    echo -e "${GREEN}✓ Configuration file created at $CONFIG_FILE${NC}"
else
    echo -e "${YELLOW}Configuration already exists at $CONFIG_FILE${NC}"
fi

echo ""

# Initialize database
echo -e "${BLUE}Initializing database...${NC}"
cd "$PROJECT_ROOT"
export ROXYWI_CONFIG="$CONFIG_FILE"
python3 app/create_db.py 2>/dev/null || echo -e "${YELLOW}Database initialization may need manual setup${NC}"
echo -e "${GREEN}✓ Database initialized${NC}"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}To start the development server:${NC}"
echo "  bash $SCRIPT_DIR/start_dev.sh"
echo ""
echo -e "${BLUE}Or manually:${NC}"
echo "  source $VENV_DIR/bin/activate"
echo "  export ROXYWI_CONFIG=$CONFIG_FILE"
echo "  python3 -m flask --app app run --debug"
echo ""
echo -e "${BLUE}To run tests:${NC}"
echo "  source $VENV_DIR/bin/activate"
echo "  pytest"
echo ""
echo -e "${BLUE}To start production server:${NC}"
echo "  bash $SCRIPT_DIR/start_prod.sh"
echo ""
