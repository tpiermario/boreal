#!/bin/bash
set -euo pipefail
script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
  echo "Questo helper è destinato ai Mac Intel." >&2; exit 1
fi
if [[ "$(id -u)" != 0 ]]; then exec /usr/bin/sudo /bin/bash "$script_path"; fi
authorized_uid="${SUDO_UID:-}"
if [[ ! "$authorized_uid" =~ ^[0-9]+$ || "$authorized_uid" -lt 501 ]]; then
  echo "Avvia lo script dall’utente che utilizzerà Boreal, tramite sudo." >&2; exit 1
fi
[[ -f dist/boreal-helper && ! -L dist/boreal-helper ]] || { echo "Prima esegui bash scripts/build.sh" >&2; exit 1; }
/usr/bin/codesign --verify --strict dist/boreal-helper
/usr/bin/codesign --verify --strict dist/borealctl
if /usr/bin/pgrep -f '/Macs Fan Control.app/Contents/MacOS/Macs Fan Control' >/dev/null; then
  echo "Chiudi Macs Fan Control prima di installare il servizio." >&2; exit 1
fi
service_label="it.boreal.fan-helper"
helper_path="/Library/PrivilegedHelperTools/$service_label"
plist_path="/Library/LaunchDaemons/$service_label.plist"
echo "Installo il servizio compilato localmente, autorizzato per UID $authorized_uid."
if [[ -L /Library/PrivilegedHelperTools || -L /Library/LaunchDaemons || -L "$helper_path" || -L "$plist_path" ]]; then
  echo "Destinazione inattesa: installazione interrotta." >&2; exit 1
fi
/bin/launchctl bootout "system/$service_label" 2>/dev/null || true
/bin/mkdir -p /Library/PrivilegedHelperTools
/usr/bin/install -o root -g wheel -m 0755 dist/boreal-helper "$helper_path"
cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$service_label</string>
<key>ProgramArguments</key><array><string>$helper_path</string><string>$authorized_uid</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>1</integer>
<key>ExitTimeOut</key><integer>5</integer>
<key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$plist_path"
/bin/chmod 0644 "$plist_path"
/usr/bin/plutil -lint "$plist_path"
/bin/launchctl bootstrap system "$plist_path"
for attempt in {1..20}; do
  if /usr/bin/sudo -u "#${authorized_uid}" "$PWD/dist/borealctl" --ping; then
    echo "Helper avviato e protocollo verificato. Nessun profilo manuale applicato."
    exit 0
  fi
  sleep 0.5
done
echo "Servizio registrato ma non raggiungibile: controlla launchctl print system/$service_label" >&2
exit 1
echo "Servizio installato. Riapri Boreal. Disinstallazione: bash scripts/uninstall-helper.sh"
