#!/bin/bash
# VOIZ CDR Recording Installer
# VOIZ Iran - Omni Channel Contact Center

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -z "${SCRIPT_SOURCE}" && "${VOIZ_CDR_BOOTSTRAPPED:-0}" != "1" ]]; then
    BOOTSTRAP_DIR=$(mktemp -d /tmp/voiz-cdr-recording.XXXXXX)
    BOOTSTRAP_ARCHIVE="${BOOTSTRAP_DIR}/source.tar.gz"
    BOOTSTRAP_REPOSITORY="${VOIZ_CDR_REPOSITORY:-https://github.com/voipiran/voiz-cdr-recording}"

    curl -fsSL "${BOOTSTRAP_REPOSITORY}/archive/refs/heads/main.tar.gz" \
        -o "${BOOTSTRAP_ARCHIVE}"
    tar -xzf "${BOOTSTRAP_ARCHIVE}" -C "${BOOTSTRAP_DIR}"
    BOOTSTRAP_SOURCE=$(find "${BOOTSTRAP_DIR}" -mindepth 1 -maxdepth 1 -type d -print -quit)
    if [[ -z "${BOOTSTRAP_SOURCE}" || ! -f "${BOOTSTRAP_SOURCE}/install.sh" ]]; then
        echo "ERROR: Complete VOIZ CDR Recording source was not found." >&2
        exit 1
    fi

    export VOIZ_CDR_BOOTSTRAPPED=1
    exec bash "${BOOTSTRAP_SOURCE}/install.sh" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
VOIZ_ROOT="${SCRIPT_DIR}"
LOG_FILE="${VOIZ_ROOT}/voiz-cdr-recording-install.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# ==========================================
# 1. Detect Issabel and extract DB credentials
# ==========================================
detect_db_credentials() {
    local rootpw=""
    local ampdbuser=""
    local ampdbpass=""

    if [[ -f /etc/issabel.conf ]]; then
        rootpw=$(sed -ne 's/^[[:space:]]*mysqlrootpwd[[:space:]]*=[[:space:]]*//p' /etc/issabel.conf 2>/dev/null | tr -d '[:space:]' || true)
    fi

    if [[ -z "${rootpw}" ]]; then
        echo -e "${RED}ERROR: Could not find mysqlrootpwd in /etc/issabel.conf${NC}"
        return 1
    fi

    log "Database root password extracted from /etc/issabel.conf"

    if [[ -f /etc/amportal.conf ]]; then
        ampdbuser=$(sed -ne 's/^[[:space:]]*AMPDBUSER[[:space:]]*=[[:space:]]*//p' /etc/amportal.conf | head -n 1 | tr -d '[:space:]')
        ampdbpass=$(sed -ne 's/^[[:space:]]*AMPDBPASS[[:space:]]*=[[:space:]]*//p' /etc/amportal.conf | head -n 1 | tr -d '[:space:]')
    fi

    export CDR_DB_NAME="asteriskcdrdb"
    if [[ -n "${ampdbuser}" && -n "${ampdbpass}" ]] &&
        mysql -h127.0.0.1 -u"${ampdbuser}" -p"${ampdbpass}" "${CDR_DB_NAME}" -e "SELECT 1" >/dev/null 2>&1; then
        export CDR_DB_USER="${ampdbuser}"
        export CDR_DB_PASS="${ampdbpass}"
        log "Using the Issabel CDR database credentials from /etc/amportal.conf"
        return 0
    fi

    if mysql -h127.0.0.1 -uroot -p"${rootpw}" "${CDR_DB_NAME}" -e "SELECT 1" >/dev/null 2>&1; then
        export CDR_DB_USER="root"
        export CDR_DB_PASS="${rootpw}"
        log "Using the root database credentials from /etc/issabel.conf"
        return 0
    fi

    echo -e "${RED}ERROR: Could not connect to ${CDR_DB_NAME} with Issabel database credentials${NC}"
    return 1
}

# ==========================================
# 2. Copy html contents to /var/www/html/
# ==========================================
install_files() {
    local target="/var/www/html"

    if [[ ! -d "${SCRIPT_DIR}/html" ]]; then
        echo -e "${RED}ERROR: html directory not found in ${SCRIPT_DIR}${NC}"
        return 1
    fi

    mkdir -p "${target}"
    cp -r "${SCRIPT_DIR}/html/." "${target}/"
    log "Copied html contents to ${target}"
    return 0
}

# ==========================================
# 3. Configure config.php with real DB password
# ==========================================
configure_config() {
    local config_file="/var/www/html/record/config.php"
    local escaped_db_user
    local escaped_db_name
    local escaped_db_pass

    if [[ ! -f "${config_file}" ]]; then
        echo -e "${RED}ERROR: config.php not found at ${config_file}${NC}"
        return 1
    fi

    escaped_db_user=$(printf '%s' "${CDR_DB_USER}" | sed "s/[\\&|]/\\\\&/g; s/'/\\\\'/g")
    escaped_db_name=$(printf '%s' "${CDR_DB_NAME}" | sed "s/[\\&|]/\\\\&/g; s/'/\\\\'/g")
    escaped_db_pass=$(printf '%s' "${CDR_DB_PASS}" | sed "s/[\\&|]/\\\\&/g; s/'/\\\\'/g")
    sed -i \
        -e "s|^[[:space:]]*'db_name'[[:space:]]*=>.*|    'db_name'     => '${escaped_db_name}',|" \
        -e "s|^[[:space:]]*'db_user'[[:space:]]*=>.*|    'db_user'     => '${escaped_db_user}',|" \
        -e "s|^[[:space:]]*'db_pass'[[:space:]]*=>.*|    'db_pass'     => '${escaped_db_pass}',|" \
        "${config_file}"
    log "Configured ${config_file} with verified database credentials"
    return 0
}

# ==========================================
# 4. Install menu.xml into Issabel menu system
# ==========================================
install_menu() {
    local menu_xml="${SCRIPT_DIR}/menu.xml"
    local menu_dest_dir="/var/www/html/modules/menu"

    if [[ ! -f "${menu_xml}" ]]; then
        log "WARNING: menu.xml not found, skipping menu installation"
        return 0
    fi

    mkdir -p "${menu_dest_dir}"
    cp -f "${menu_xml}" "${menu_dest_dir}/menu-cdr-recording.xml"
    log "Installed menu.xml to ${menu_dest_dir}/menu-cdr-recording.xml"

    # Attempt to reload Issabel menus if command exists
    if command -v issabel-menumerge >/dev/null 2>&1; then
        issabel-menumerge "${menu_xml}" 2>/dev/null || log "WARNING: issabel-menumerge failed (menus may need manual reload)"
    elif command -v amportal >/dev/null 2>&1; then
        amportal a reload 2>/dev/null || log "WARNING: amportal reload failed (menus may need manual reload)"
    fi

    return 0
}

# ==========================================
# 5. Set monitor directory permissions
# ==========================================
fix_monitor_permissions() {
    local monitor_dir="/var/spool/asterisk/monitor"

    if [[ -d "${monitor_dir}" ]]; then
        chmod -R o+r "${monitor_dir}" 2>/dev/null || true
        log "Set read permissions on ${monitor_dir}"
    else
        log "WARNING: ${monitor_dir} not found. You may need to set permissions manually."
    fi
    return 0
}

# ==========================================
# Main
# ==========================================
main() {
    > "${LOG_FILE}"
    echo -e "${CYAN}VOIZ CDR Recording Installer${NC}"
    echo "============================="
    echo

    detect_db_credentials || exit 1
    install_files || exit 1
    configure_config || exit 1
    install_menu
    fix_monitor_permissions

    echo
    echo -e "${GREEN}Installation completed successfully.${NC}"
    echo "Access URL: https://<Issabel_IP>/record/monitoring.php"
    echo "Log file: ${LOG_FILE}"
}

main "$@"
