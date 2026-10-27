#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then exit 1; fi
script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
if [[ "$(id -u)" != 0 ]]; then exec /usr/bin/sudo /bin/bash "$script_path"; fi
service_label="it.boreal.fan-helper"
/bin/launchctl bootout "system/$service_label" 2>/dev/null || true
# The daemon attempts restoration on SIGTERM before launchctl returns.
/bin/rm -f "/Library/LaunchDaemons/$service_label.plist"
/bin/rm -f "/Library/PrivilegedHelperTools/$service_label"
echo "Servizio rimosso. Se il ripristino SMC non era riuscito, riavvia il Mac per ripristinare la gestione di sistema."
