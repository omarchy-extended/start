#!/bin/bash
# Removes what install.sh added.
set -uo pipefail
omarchy plugin disable omext.start >/dev/null 2>&1
[[ -L $HOME/.config/omarchy/plugins/omext.start ]] && rm "$HOME/.config/omarchy/plugins/omext.start"
hypr_conf=$HOME/.config/hypr/hyprland.lua
[[ -f $hypr_conf ]] && sed -i "/^-- BEGIN omext-start\$/,/^-- END omext-start\$/d" "$hypr_conf" && hyprctl reload >/dev/null
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
[[ -f $menu_conf ]] && sed -i "\|^ *// BEGIN omext-start\$|,\|^ *// END omext-start\$|d" "$menu_conf"
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/omext/start/disabled"
# (Omarchy's dock, if it was off for Start: omext core turns it back on.)
# Omarchy's own menu button, if Start had its place: back on the bar.
jq -e '.replaceMenuButton == true' "${XDG_CONFIG_HOME:-$HOME/.config}/omext/start.json" >/dev/null 2>&1 && "$(dirname "$(readlink -f "$0")")/plugins/omext.start/menu-button.sh" give || true
echo "uninstall: done"
