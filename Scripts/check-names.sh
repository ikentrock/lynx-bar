#!/bin/zsh
# Fails if Ice-derived code names remain outside the allowlist, or if a stored key's raw
# value changed (see docs/superpowers/specs/2026-10-02-lynx-bar-internal-rename-design.md,
# "What must not change"). Also prints remaining prose mentions of "Ice" for review.
cd "${0:A:h}/.."
set -o pipefail
failed=0

ALLOW='"(ShowIceIcon|IceIcon|CustomIceIconIsTemplate|UseIceBar|IceBarLocation|EnableIceBar|Ice Cube)"|Ice\.ControlItem\.|IceSettingsImporter|com\.jordanbaird\.Ice|hasImportedIceSettings|legacyIceCube|jordanbaird/Ice'

# Code identifiers containing Ice/ice: IceFoo, fooIce, iceFoo.
hits=$(git grep -nP '\bIce[A-Z]\w*|\b[a-z]\w*Ice\w*|\bice[A-Z]\w*' -- 'LynxBar/*.swift' 'Shared/*.swift' 'MenuBarItemService/*.swift' 'Scripts/*' ':!Scripts/check-names.sh' \
    | grep -vE "$ALLOW")
if [[ -n $hits ]]; then
    echo "Ice-derived names outside the allowlist:"; echo "$hits"; failed=1
fi

# The header comment of every LynxBar file must say LynxBar.
headers=$(git grep -lE '^//  Ice$' -- 'LynxBar/*.swift')
if [[ -n $headers ]]; then
    echo "Files with the old //  Ice header:"; echo "$headers"; failed=1
fi

# Stored keys must keep their raw values, or saved settings silently reset.
typeset -A KEYS=(
    'case showLynxIcon = "ShowIceIcon"' LynxBar/Utilities/Defaults.swift
    'case lynxIcon = "IceIcon"' LynxBar/Utilities/Defaults.swift
    'case customLynxIconIsTemplate = "CustomIceIconIsTemplate"' LynxBar/Utilities/Defaults.swift
    'case useLynxShelf = "UseIceBar"' LynxBar/Utilities/Defaults.swift
    'case lynxShelfLocation = "IceBarLocation"' LynxBar/Utilities/Defaults.swift
    'case enableLynxShelf = "EnableIceBar"' LynxBar/Hotkeys/HotkeyAction.swift
    'case visible = "Ice.ControlItem.Visible"' LynxBar/MenuBar/ControlItem/ControlItem.swift
    'case hidden = "Ice.ControlItem.Hidden"' LynxBar/MenuBar/ControlItem/ControlItem.swift
    'case alwaysHidden = "Ice.ControlItem.AlwaysHidden"' LynxBar/MenuBar/ControlItem/ControlItem.swift
)
for line file in ${(kv)KEYS}; do
    if ! grep -qF "$line" "$file"; then
        echo "Stored key changed or missing in $file: $line"; failed=1
    fi
done

if (( failed )); then
    exit 1
fi

prose=$(git grep -nP '\bIce\b' -- 'LynxBar/*.swift' | grep -vE "$ALLOW|Based on Ice")
if [[ -n $prose ]]; then
    echo "Note: remaining mentions of Ice (expected only where they refer to upstream Ice):"
    echo "$prose"
fi
echo "PASS check-names"
