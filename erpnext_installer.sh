#!/usr/bin/env bash
# ==============================================================================
# ERPNext / Frappe Bench Installer (Interactive + CLI)
#
# Copyright (c) 2026 Mario Magdy Samy (Recipe Codes)
# Company: Recipe Codes
# Website: https://recipe.codes
# Repository: https://github.com/mariomsamy/erpnext_optimized
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ==============================================================================
#
# Supports ERPNext/Frappe v13–v16 (best-effort), Ubuntu/Debian
#
# Usage (non-interactive example):
#   sudo -E bash install-erpnext.sh --version 15 --site erp.example.com --prod \
#     --db-root-pass 'StrongDBPass' --admin-pass 'StrongAdminPass' --install-erpnext yes --install-hrms no --ssl no
#
# Interactive:
#   bash install-erpnext.sh
# ==============================================================================

set -Eeuo pipefail

# -----------------------------
# Logging + error handling
# -----------------------------
LOG_FILE="${LOG_FILE:-/var/log/erpnext-installer.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true

log()  { printf '%s\n' "$*" | tee -a "$LOG_FILE" >/dev/null; }
die()  { log "ERROR: $*"; exit 1; }

trap 'die "Failed at line $LINENO. Check log: $LOG_FILE"' ERR

# -----------------------------
# Colors (only if TTY)
# -----------------------------
if [[ -t 1 ]]; then
  YELLOW=$'\033[1;33m'
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  BLUE=$'\033[1;34m'
  NC=$'\033[0m'
else
  YELLOW=""; GREEN=""; RED=""; BLUE=""; NC=""
fi

say()  { log "${BLUE}$*${NC}"; }
ok()   { log "${GREEN}$*${NC}"; }
warn() { log "${YELLOW}$*${NC}"; }
bad()  { log "${RED}$*${NC}"; }

# -----------------------------
# Helpers
# -----------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

ver_ge() { # ver_ge A B => true if A >= B
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

lower() { tr '[:upper:]' '[:lower:]' <<<"${1:-}"; }

server_ip() {
  (hostname -I 2>/dev/null | awk '{print $1}') || true
}

# -----------------------------
# Defaults + CLI args
# -----------------------------
ERP_VERSION=""        # 13|14|15|16
BENCH_BRANCH=""       # version-13 etc
SITE_NAME=""
DB_ROOT_PASS=""
ADMIN_PASS=""
DO_PROD=""            # yes/no
INSTALL_ERPNEXT=""    # yes/no
INSTALL_HRMS=""       # yes/no
DO_SSL=""             # yes/no
EMAIL_ADDR=""

ASSUME_YES="${ASSUME_YES:-0}"
FRAPPE_USER="${FRAPPE_USER:-$SUDO_USER}"
FRAPPE_HOME=""
DISTRO=""
DISTRO_VER=""

usage() {
  cat <<EOF
ERPNext Installer (Recipe Codes)

Website: https://recipe.codes
Repo:    https://github.com/mariomsamy/erpnext_optimized

Options:
  --version           13|14|15|16
  --site              site name (FQDN recommended for SSL)
  --db-root-pass       MariaDB root password (will be set/updated)
  --admin-pass         ERPNext Administrator password
  --prod               yes|no   (production setup)
  --install-erpnext    yes|no
  --install-hrms       yes|no
  --ssl                yes|no
  --email              email for certbot
  --assume-yes         skip prompts where possible
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) ERP_VERSION="${2:-}"; shift 2;;
    --site) SITE_NAME="${2:-}"; shift 2;;
    --db-root-pass) DB_ROOT_PASS="${2:-}"; shift 2;;
    --admin-pass) ADMIN_PASS="${2:-}"; shift 2;;
    --prod) DO_PROD="$(lower "${2:-}")"; shift 2;;
    --install-erpnext) INSTALL_ERPNEXT="$(lower "${2:-}")"; shift 2;;
    --install-hrms) INSTALL_HRMS="$(lower "${2:-}")"; shift 2;;
    --ssl) DO_SSL="$(lower "${2:-}")"; shift 2;;
    --email) EMAIL_ADDR="${2:-}"; shift 2;;
    --assume-yes) ASSUME_YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

# -----------------------------
# Root / sudo
# -----------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "Run as root (recommended: sudo -E bash $0 ...)."
fi

# Determine target user for bench (default: sudo user)
if [[ -z "${FRAPPE_USER:-}" || "${FRAPPE_USER}" == "root" ]]; then
  die "Refusing to install bench as root. Run via sudo so FRAPPE_USER is a non-root user (or set FRAPPE_USER)."
fi

FRAPPE_HOME="$(eval echo "~$FRAPPE_USER")"
[[ -d "$FRAPPE_HOME" ]] || die "Cannot resolve home for user: $FRAPPE_USER"

say "ERPNext Installer - Recipe Codes"
say "Website: https://recipe.codes"
say "Repository: https://github.com/mariomsamy/erpnext_optimized"
say "Installing as user: $FRAPPE_USER (home: $FRAPPE_HOME)"
say "Log file: $LOG_FILE"

# -----------------------------
# OS detection
# -----------------------------
need_cmd awk
need_cmd sort

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  DISTRO="${ID:-}"
  DISTRO_VER="${VERSION_ID:-}"
else
  die "Cannot detect OS (missing /etc/os-release)."
fi

case "$DISTRO" in
  ubuntu|debian) ;;
  *) die "Unsupported distro: ${DISTRO}. Supported: Ubuntu, Debian." ;;
esac

say "Detected OS: $DISTRO $DISTRO_VER"

# -----------------------------
# Version selection + mapping
# -----------------------------
choose_version_interactive() {
  say "Select ERPNext/Frappe version to install:"
  local choices=("13" "14" "15" "16")
  select v in "${choices[@]}"; do
    case "${v:-}" in
      13|14|15|16) ERP_VERSION="$v"; break;;
      *) warn "Invalid selection."; ;;
    esac
  done
}

if [[ -z "$ERP_VERSION" ]]; then
  choose_version_interactive
fi

case "$ERP_VERSION" in
  13) BENCH_BRANCH="version-13" ;;
  14) BENCH_BRANCH="version-14" ;;
  15) BENCH_BRANCH="version-15" ;;
  16) BENCH_BRANCH="version-16" ;;
  *) die "Invalid --version. Use 13|14|15|16." ;;
esac

REQ_PY="3.10"
REQ_NODE="18"
if [[ "$ERP_VERSION" == "16" ]]; then
  REQ_PY="3.14"
  REQ_NODE="24"
fi

say "Selected: ERPNext/Frappe v$ERP_VERSION (bench branch: $BENCH_BRANCH)"
say "Min requirements: Python >= $REQ_PY, Node >= $REQ_NODE"

# Practical OS guardrails for v16 (Python 3.14+)
if [[ "$ERP_VERSION" == "16" ]]; then
  if [[ "$DISTRO" == "ubuntu" ]]; then
    ver_ge "$DISTRO_VER" "24.04" || die "v16 requires Ubuntu 24.04+ in this installer (Python 3.14+)."
  fi
fi

# -----------------------------
# Prompts
# -----------------------------
ask_yes_no() {
  local prompt="$1"
  local def="${2:-no}"
  local ans=""
  if [[ "$ASSUME_YES" == "1" ]]; then
    echo "$def"
    return 0
  fi
  while true; do
    read -r -p "$prompt [yes/no] (default: $def): " ans
    ans="$(lower "${ans:-$def}")"
    case "$ans" in
      y|yes) echo "yes"; return 0;;
      n|no)  echo "no";  return 0;;
      *) warn "Please answer yes or no.";;
    esac
  done
}

ask_secret_twice() {
  local prompt="$1"
  local v1 v2
  while true; do
    read -r -s -p "$prompt: " v1; echo
    read -r -s -p "Confirm: " v2; echo
    [[ -n "$v1" ]] || { warn "Empty value not allowed."; continue; }
    [[ "$v1" == "$v2" ]] || { warn "Values do not match. Try again."; continue; }
    printf '%s' "$v1"
    return 0
  done
}

if [[ -z "$DO_PROD" ]]; then
  DO_PROD="$(ask_yes_no "Do production setup (nginx + supervisor)?" "yes")"
fi

if [[ -z "$SITE_NAME" ]]; then
  read -r -p "Enter site name (FQDN recommended if SSL): " SITE_NAME
  [[ -n "$SITE_NAME" ]] || die "Site name is required."
fi

if [[ -z "$DB_ROOT_PASS" ]]; then
  warn "MariaDB root password will be configured/updated."
  DB_ROOT_PASS="$(ask_secret_twice "Enter MariaDB root password")"
fi

if [[ -z "$ADMIN_PASS" ]]; then
  ADMIN_PASS="$(ask_secret_twice "Enter ERPNext Administrator password")"
fi

if [[ -z "$INSTALL_ERPNEXT" ]]; then
  INSTALL_ERPNEXT="$(ask_yes_no "Install ERPNext app?" "yes")"
fi

if [[ "$DO_PROD" == "yes" && -z "$INSTALL_HRMS" ]]; then
  INSTALL_HRMS="$(ask_yes_no "Install HRMS app?" "no")"
fi

if [[ "$DO_PROD" == "yes" && -z "$DO_SSL" ]]; then
  DO_SSL="$(ask_yes_no "Install SSL via certbot now?" "no")"
fi

if [[ "$DO_SSL" == "yes" && -z "$EMAIL_ADDR" ]]; then
  read -r -p "Enter email for Let's Encrypt: " EMAIL_ADDR
  [[ -n "$EMAIL_ADDR" ]] || die "Email is required for SSL."
fi

# -----------------------------
# APT setup
# -----------------------------
export DEBIAN_FRONTEND=noninteractive
APT="apt-get -y -o Dpkg::Options::=--force-confnew"

say "Updating system packages..."
$APT update | tee -a "$LOG_FILE"
$APT upgrade | tee -a "$LOG_FILE"
ok "System updated."

say "Installing base dependencies..."
$APT install sudo ca-certificates curl git gnupg lsb-release software-properties-common \
  build-essential pkg-config libffi-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libncursesw5-dev xz-utils tk-dev liblzma-dev wget | tee -a "$LOG_FILE"
ok "Base dependencies installed."

# -----------------------------
# Redis / MariaDB / wkhtmltopdf
# -----------------------------
say "Installing Redis, MariaDB, and PDF dependencies..."
$APT install redis-server mariadb-server mariadb-client \
  xvfb fontconfig wkhtmltopdf | tee -a "$LOG_FILE" || {
    warn "wkhtmltopdf install failed from distro repos. Retrying with minimal deps..."
    $APT install xvfb fontconfig | tee -a "$LOG_FILE"
  }
ok "Database/cache/pdf dependencies installed."

# MariaDB hardening (idempotent marker)
MARKER_FILE="$FRAPPE_HOME/.mariadb_configured.marker"
if [[ ! -f "$MARKER_FILE" ]]; then
  say "Configuring MariaDB root password and basic hardening..."
  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';" 2>/dev/null || true
  mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='';" || true
  mysql -u root -p"${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS test;" || true
  mysql -u root -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;" || true

  say "Applying utf8mb4 defaults..."
  cat >/etc/mysql/conf.d/frappe.cnf <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF
  systemctl restart mariadb
  touch "$MARKER_FILE"
  ok "MariaDB configured."
else
  ok "MariaDB already configured (marker found)."
fi

# -----------------------------
# Python setup
# -----------------------------
need_cmd python3 || true

current_py="0.0"
if command -v python3 >/dev/null 2>&1; then
  current_py="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")"
fi
say "Detected Python: $current_py"

if ! ver_ge "$current_py" "$REQ_PY"; then
  if [[ "$ERP_VERSION" == "16" ]]; then
    die "Python $REQ_PY+ is required for v16, but system has $current_py. Install Python 3.14+ then re-run."
  fi

  warn "Python $REQ_PY+ required, but system has $current_py. Installing newer Python via OS repos where possible..."
  if [[ "$DISTRO" == "ubuntu" ]]; then
    add-apt-repository -y ppa:deadsnakes/ppa | tee -a "$LOG_FILE"
    $APT update | tee -a "$LOG_FILE"
    $APT install "python${REQ_PY}" "python${REQ_PY}-dev" "python${REQ_PY}-venv" | tee -a "$LOG_FILE"
    update-alternatives --install /usr/bin/python3 python3 "/usr/bin/python${REQ_PY}" 2 || true
  else
    die "On Debian, install Python $REQ_PY+ (backports/custom build) then re-run."
  fi
fi

$APT install python3-dev python3-venv python3-pip | tee -a "$LOG_FILE"
python3 -m pip install --upgrade pip setuptools wheel | tee -a "$LOG_FILE" || true

# -----------------------------
# Node + Yarn via nvm
# -----------------------------
say "Installing nvm..."
sudo -u "$FRAPPE_USER" bash -lc \
  'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' | tee -a "$LOG_FILE"

NVM_LOAD='export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
sudo -u "$FRAPPE_USER" bash -lc \
  "$NVM_LOAD; nvm install ${REQ_NODE}; nvm alias default ${REQ_NODE}; node -v; npm -v" | tee -a "$LOG_FILE"

sudo -u "$FRAPPE_USER" bash -lc \
  "$NVM_LOAD; corepack enable || true; (yarn -v || npm i -g yarn)" | tee -a "$LOG_FILE"

ok "Node + Yarn installed (Node >= $REQ_NODE)."

# -----------------------------
# Bench installation (pipx preferred)
# -----------------------------
say "Installing bench..."
$APT install pipx | tee -a "$LOG_FILE" || true
sudo -u "$FRAPPE_USER" bash -lc 'python3 -m pipx ensurepath' | tee -a "$LOG_FILE" || true

if sudo -u "$FRAPPE_USER" bash -lc 'command -v pipx >/dev/null 2>&1'; then
  sudo -u "$FRAPPE_USER" bash -lc 'pipx install frappe-bench || pipx upgrade frappe-bench' | tee -a "$LOG_FILE"
else
  warn "pipx not available; falling back to pip install."
  python3 -m pip config --global set global.break-system-packages true || true
  python3 -m pip install --upgrade frappe-bench | tee -a "$LOG_FILE"
fi

# -----------------------------
# Bench init + site creation
# -----------------------------
say "Initializing bench..."
sudo -u "$FRAPPE_USER" bash -lc "
  set -e
  $NVM_LOAD
  cd '$FRAPPE_HOME'
  if [[ -d frappe-bench ]]; then
    echo 'frappe-bench already exists; skipping bench init.'
  else
    bench init frappe-bench --version '$BENCH_BRANCH' --verbose
  fi
" | tee -a "$LOG_FILE"
ok "Bench initialized."

say "Creating site: $SITE_NAME"
sudo -u "$FRAPPE_USER" bash -lc "
  set -e
  $NVM_LOAD
  cd '$FRAPPE_HOME/frappe-bench'
  chmod o+rx '$FRAPPE_HOME' || true
  bench new-site '$SITE_NAME' --db-root-password '$DB_ROOT_PASS' --admin-password '$ADMIN_PASS'
" | tee -a "$LOG_FILE"
ok "Site created."

# -----------------------------
# Install ERPNext (+ HRMS optionally)
# -----------------------------
if [[ "$INSTALL_ERPNEXT" == "yes" ]]; then
  say "Installing ERPNext app..."
  sudo -u "$FRAPPE_USER" bash -lc "
    set -e
    $NVM_LOAD
    cd '$FRAPPE_HOME/frappe-bench'
    bench get-app erpnext --branch '$BENCH_BRANCH'
    bench --site '$SITE_NAME' install-app erpnext
  " | tee -a "$LOG_FILE"
  ok "ERPNext installed."
else
  warn "Skipping ERPNext install (bench + site only)."
fi

# -----------------------------
# Production setup
# -----------------------------
if [[ "$DO_PROD" == "yes" ]]; then
  say "Installing production prerequisites (nginx, supervisor)..."
  $APT install nginx supervisor fail2ban | tee -a "$LOG_FILE" || true

  say "Running bench production setup..."
  sudo -u "$FRAPPE_USER" bash -lc "
    set -e
    $NVM_LOAD
    cd '$FRAPPE_HOME/frappe-bench'
    sudo bench setup production '$FRAPPE_USER' --yes
    bench --site '$SITE_NAME' scheduler enable
    bench --site '$SITE_NAME' scheduler resume
  " | tee -a "$LOG_FILE"
  ok "Production setup complete."

  if [[ "$INSTALL_HRMS" == "yes" ]]; then
    say "Installing HRMS app..."
    sudo -u "$FRAPPE_USER" bash -lc "
      set -e
      $NVM_LOAD
      cd '$FRAPPE_HOME/frappe-bench'
      bench get-app hrms --branch '$BENCH_BRANCH'
      bench --site '$SITE_NAME' install-app hrms
    " | tee -a "$LOG_FILE"
    ok "HRMS installed."
  fi

  if [[ "$DO_SSL" == "yes" ]]; then
    say "Installing certbot and issuing certificate..."
    $APT install snapd | tee -a "$LOG_FILE" || true
    snap install core >/dev/null 2>&1 || true
    snap refresh core >/dev/null 2>&1 || true
    snap install --classic certbot | tee -a "$LOG_FILE"
    ln -sf /snap/bin/certbot /usr/bin/certbot

    certbot --nginx --non-interactive --agree-tos --email "$EMAIL_ADDR" -d "$SITE_NAME" | tee -a "$LOG_FILE"
    ok "SSL installed."
  fi

  ok "All done (production)."
else
  say "Development mode selected."
  sudo -u "$FRAPPE_USER" bash -lc "
    set -e
    $NVM_LOAD
    cd '$FRAPPE_HOME/frappe-bench'
    bench use '$SITE_NAME'
    bench build
  " | tee -a "$LOG_FILE"
  ok "Development environment ready."
fi

# -----------------------------
# Summary
# -----------------------------
IP="$(server_ip)"
log ""
log "--------------------------------------------------------------------------------"
ok "Installation completed for ERPNext/Frappe v$ERP_VERSION (branch: $BENCH_BRANCH)."
log "Recipe Codes: https://recipe.codes"
log "Repo:        https://github.com/mariomsamy/erpnext_optimized"
if [[ "$DO_PROD" == "yes" ]]; then
  if [[ "$DO_SSL" == "yes" ]]; then
    log "Access: https://$SITE_NAME"
  else
    log "Access: http://$SITE_NAME  (or http://$IP if DNS not set)"
  fi
else
  log "Start dev server:"
  log "  sudo -u $FRAPPE_USER bash -lc 'cd $FRAPPE_HOME/frappe-bench && bench start'"
  log "Then open: http://$IP:8000"
fi
log "Log file: $LOG_FILE"
log "--------------------------------------------------------------------------------"
