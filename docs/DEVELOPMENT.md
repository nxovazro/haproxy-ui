# Roxy-WI Development Guide

This guide explains how to set up and run Roxy-WI from source code for development and testing.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Development Server](#development-server)
4. [Production Server](#production-server)
5. [Database Setup](#database-setup)
6. [Configuration](#configuration)
7. [Development Commands](#development-commands)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

- **Python 3.8+** - Required for running the application
- **Git** - For cloning the repository
- **pip** - Python package manager (usually comes with Python)
- **Make** - Optional but recommended (for using Makefile commands)

### System Dependencies

Some Python packages require system libraries. Install them based on your OS:

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    python3-dev \
    python3-pip \
    python3-venv \
    libssl-dev \
    libffi-dev \
    libmysqlclient-dev \
    build-essential
```

**CentOS/RHEL/Fedora:**
```bash
sudo yum install -y \
    python3-devel \
    python3-pip \
    openssl-devel \
    libffi-devel \
    mysql-devel \
    gcc
```

**macOS:**
```bash
brew install python3 libssl libffi
```

## Quick Start

The fastest way to get started:

```bash
# Clone the repository
git clone https://github.com/nxovazro/haproxy-ui.git
cd haproxy-ui

# Run setup script (one-time initialization)
bash scripts/setup_dev_env.sh

# Start the development server
bash scripts/start_dev.sh
```

Then open your browser to http://localhost:5000 and log in with `admin/admin`.

## Development Server

### Using the Startup Script

```bash
bash scripts/start_dev.sh
```

This script will:
1. Create a Python virtual environment
2. Install all dependencies
3. Initialize the database
4. Start the Flask development server on http://localhost:5000

### Manual Startup

If you prefer to start manually:

```bash
# Activate virtual environment
source venv/bin/activate

# Set development configuration
export ROXYWI_CONFIG=.roxy-wi-dev/etc/roxy-wi.cfg

# Initialize database (first time only)
python3 app/create_db.py

# Start development server
python3 -m flask --app app run --debug
```

### Using Make

```bash
make setup       # Initial setup
make dev         # Start development server
make test        # Run tests
make clean       # Clean up files
```

### Environment Variables

Create a `.env.development` file for your development settings:

```bash
cp .env.development .env
# Edit .env with your settings
```

Key variables:
- `ROXYWI_TESTING=0` - Run in development mode
- `ROXYWI_LOG_LEVEL=DEBUG` - Enable debug logging
- `ROXYWI_SCHEDULER_ENABLED=0` - Disable background scheduler in dev

## Production Server

### Using Gunicorn

For production deployment, use Gunicorn:

```bash
bash scripts/start_prod.sh
```

Or manually:

```bash
gunicorn --workers=4 --threads=2 --bind=0.0.0.0:8000 'app:app'
```

### Configuration

```bash
# Install Gunicorn if not already installed
pip install gunicorn

# Create production config
cp .env.production .env.prod
# Edit .env.prod with production settings
```

### With Systemd (Recommended)

Create `/etc/systemd/system/roxy-wi.service`:

```ini
[Unit]
Description=Roxy-WI Web Interface
After=network.target

[Service]
Type=notify
User=roxy-wi
WorkingDirectory=/var/www/haproxy-ui
Environment="ROXYWI_CONFIG=/etc/roxy-wi/roxy-wi.cfg"
ExecStart=/path/to/venv/bin/gunicorn \
    --workers=4 \
    --threads=2 \
    --bind=unix:/var/run/roxy-wi/roxy-wi.sock \
    --access-logfile=/var/log/roxy-wi/access.log \
    --error-logfile=/var/log/roxy-wi/error.log \
    'app:app'

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl start roxy-wi
sudo systemctl enable roxy-wi
```

## Database Setup

### SQLite (Development)

SQLite is used by default in development. No additional setup needed beyond running the initialization:

```bash
python3 app/create_db.py
```

Database file will be created at `.roxy-wi-dev/lib/roxywi.db`

### MySQL/MariaDB (Production)

For production, MySQL or MariaDB is recommended:

1. **Create database:**
```bash
mysql -u root -p -e "CREATE DATABASE roxywi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p -e "CREATE USER 'roxy-wi'@'localhost' IDENTIFIED BY 'secure_password';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON roxywi.* TO 'roxy-wi'@'localhost';"
mysql -u root -p -e "FLUSH PRIVILEGES;"
```

2. **Configure in `.env` or config file:**
```ini
[mysql]
enable = 1
mysql_host = localhost
mysql_port = 3306
mysql_user = roxy-wi
mysql_password = secure_password
mysql_db = roxywi
```

3. **Initialize database:**
```bash
python3 app/create_db.py
python3 app/migrate.py migrate
```

## Configuration

### Configuration Files

Configuration can be set via:
1. Config file: `/etc/roxy-wi/roxy-wi.cfg` (production) or `.roxy-wi-dev/etc/roxy-wi.cfg` (development)
2. Environment variables: `ROXYWI_*` prefixed variables
3. `.env` file for development

### Main Configuration

Create or edit configuration file:

```ini
[main]
fullpath = /path/to/haproxy-ui
log_path = /var/log/roxy-wi
lib_path = /var/lib/roxy-wi
# Generate with: python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
secret_phrase = YOUR_SECRET_KEY_HERE

[configs]
haproxy_save_configs_dir = /var/lib/roxy-wi/configs/hap_config/
keepalived_save_configs_dir = /var/lib/roxy-wi/configs/kp_config/
nginx_save_configs_dir = /var/lib/roxy-wi/configs/nginx_config/
apache_save_configs_dir = /var/lib/roxy-wi/configs/apache_config/

[mysql]
enable = 0  # Set to 1 for MySQL
mysql_host = 127.0.0.1
mysql_port = 3306
mysql_user = roxy-wi
mysql_password = roxy-wi
mysql_db = roxywi
```

### Environment Variables

Key environment variables:

```bash
# Database
ROXYWI_MYSQL_HOST=localhost
ROXYWI_MYSQL_USER=roxy-wi
ROXYWI_MYSQL_PASSWORD=password

# Logging
ROXYWI_LOG_PATH=/var/log/roxy-wi
ROXYWI_LOG_LEVEL=INFO

# Security
ROXYWI_SECRET_PHRASE=your-secret-key-here

# JWT
ROXYWI_JWT_ALGORITHM=HS256
ROXYWI_JWT_EXPIRES_HOURS=1

# Scheduler
ROXYWI_SCHEDULER_ENABLED=0  # Enable on one instance only

# Initial admin password
ROXYWI_BOOTSTRAP_ADMIN_PASSWORD=initial_secure_password
```

## Development Commands

### Using Makefile

```bash
make help           # Show all available commands
make setup          # Setup development environment
make dev            # Run development server
make prod           # Run production server
make test           # Run tests
make test-cov       # Run tests with coverage
make lint           # Check code style
make format         # Format code with black
make migrate        # Run database migrations
make init-db        # Initialize database
make clean          # Clean up generated files
make logs           # View application logs
```

### Running Tests

```bash
# Activate virtual environment
source venv/bin/activate

# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific test file
pytest tests/test_module.py

# Run with coverage report
pytest --cov=app --cov-report=html
```

### Linting and Formatting

```bash
# Check code style
flake8 app/ tests/

# Format code
black app/ tests/

# Format check only
black --check app/ tests/
```

### Database Migrations

```bash
# Create new migration
python3 app/migrate.py create migration_name

# Apply pending migrations
python3 app/migrate.py migrate

# Rollback migrations
python3 app/migrate.py rollback --steps 1
```

### Running Scheduler

The background scheduler should run on a dedicated instance:

```bash
python3 scheduler_runner.py
```

## Troubleshooting

### Permission Denied Error

If you get permission errors on scripts:

```bash
chmod +x scripts/*.sh
```

### Port Already in Use

If port 5000 is already in use:

```bash
# Change port in script or run:
python3 -m flask --app app run --debug --port 8000
```

### Database Errors

If you get database errors:

```bash
# Recreate database
rm .roxy-wi-dev/lib/*.db 2>/dev/null || true
python3 app/create_db.py
python3 app/migrate.py migrate
```

### Missing Dependencies

If you get import errors:

```bash
# Reinstall dependencies
source venv/bin/activate
pip install --upgrade -r requirements.txt -r requirements-dev.txt
```

### Virtual Environment Issues

If virtual environment is corrupted:

```bash
# Remove and recreate
rm -rf venv/
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Log Files

Check logs for errors:

```bash
# Development logs
tail -f logs/roxy-wi.log

# Web server logs (Gunicorn)
tail -f /var/log/roxy-wi/error.log
tail -f /var/log/roxy-wi/access.log
```

### Default Credentials

After initial setup:
- **URL:** http://localhost:5000 (development) or https://your-server (production)
- **Default username:** admin
- **Default password:** admin

**⚠️ IMPORTANT:** Change the default password immediately in production!

## Additional Resources

- [Flask Documentation](https://flask.palletsprojects.com/)
- [Gunicorn Documentation](https://docs.gunicorn.org/)
- [Peewee ORM Documentation](http://docs.peewee-orm.com/)
- [Official Roxy-WI Documentation](https://roxy-wi.org/)

## Getting Help

For issues and questions:
- [GitHub Issues](https://github.com/nxovazro/haproxy-ui/issues)
- [Official Forum](https://roxy-wi.org/)
- [Telegram Community](https://t.me/roxy_wi_channel)
