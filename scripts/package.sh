#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d dist/Boreal.app && -f dist/boreal-helper && -f dist/borealctl ]] || { echo 'Esegui prima bash scripts/build.sh' >&2; exit 1; }
out="${1:-$PWD/dist/Boreal-0.2.5-Intel.dmg}"
[[ ! -e "$out" ]] || { echo "Il file esiste già: $out" >&2; exit 1; }
case "$out" in /*) ;; *) out="$PWD/$out";; esac
mkdir -p "$(dirname "$out")"
stage="$(mktemp -d "${TMPDIR:-/tmp}/boreal-package.XXXXXX")"
mounted=0
cleanup() {
    if [[ "$mounted" == 1 ]]; then hdiutil detach "$stage/volume" >/dev/null || return; fi
    rm -rf "$stage"
}
trap cleanup EXIT
hdiutil convert Packaging/layout.dmg -format UDRW -o "$stage/writable.dmg" >/dev/null
mkdir "$stage/volume"
hdiutil attach -nobrowse -mountpoint "$stage/volume" "$stage/writable.dmg" >/dev/null
mounted=1
ditto --norsrc dist/Boreal.app "$stage/volume/Boreal.app"
support="$stage/volume/Opzioni/Supporto"
mkdir -p "$support/dist" "$support/scripts"
cp dist/boreal-helper dist/borealctl "$support/dist/"
cp scripts/install-helper.sh scripts/uninstall-helper.sh "$support/scripts/"
cp LICENSE "$stage/volume/Opzioni/LICENZA.txt"
cp Packaging/LEGGIMI.txt "$stage/volume/Opzioni/LEGGIMI.txt"
cat > "$stage/volume/Opzioni/Installa controllo ventole.command" <<'CMD'
#!/bin/bash
exec /bin/bash "$(dirname "$0")/Supporto/scripts/install-helper.sh"
CMD
cat > "$stage/volume/Opzioni/Rimuovi controllo ventole.command" <<'CMD'
#!/bin/bash
exec /bin/bash "$(dirname "$0")/Supporto/scripts/uninstall-helper.sh"
CMD
chmod +x "$stage/volume/Opzioni/"*.command
xattr -cr "$stage/volume/Boreal.app"
codesign --verify --strict "$stage/volume/Boreal.app"
hdiutil detach "$stage/volume" >/dev/null
mounted=0
hdiutil convert "$stage/writable.dmg" -format ULMO -o "$out"
hdiutil verify "$out"
shasum -a 256 "$out"
