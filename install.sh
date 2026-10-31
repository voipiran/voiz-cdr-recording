#!/bin/bash
# VOIZ CDR Recording Installer
# VOIZ Iran - Omni Channel Contact Center

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
# 1. Detect Issabel and extract DB password
# ==========================================
detect_db_password() {
    local rootpw=""
    if [[ -f /etc/issabel.conf ]]; then
        rootpw=$(sed -ne 's/.*mysqlrootpwd=//gp' /etc/issabel.conf 2>/dev/null || true)
    fi

    if [[ -z "${rootpw}" ]]; then
        echo -e "${RED}ERROR: Could not find mysqlrootpwd in /etc/issabel.conf${NC}"
        return 1
    fi

    export CDR_DB_PASS="${rootpw}"
    log "Database password extracted from /etc/issabel.conf"
    return 0
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

    if [[ ! -f "${config_file}" ]]; then
        echo -e "${RED}ERROR: config.php not found at ${config_file}${NC}"
        return 1
    fi

    sed -i "s/'db_pass' *=> *'database_password'/'db_pass' => '${CDR_DB_PASS}'/" "${config_file}"
    log "Configured ${config_file} with database password"
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

    detect_db_password || exit 1
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
