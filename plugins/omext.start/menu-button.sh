#!/bin/bash
# Start in the place of Omarchy's own menu button on the bar (Start's Settings ›
# Bar button › In place of Omarchy's menu button).
#   take   Omarchy's button leaves the bar, and Start's goes where it was
#   give   Omarchy's button is back, just before Start's (or first at the left,
#          with Start's not on the bar)
# Omarchy's menu itself is untouched: its keys, and a right click on Start's button.
conf=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json
[[ -s $conf ]] || exit 0

case ${1:-} in
  take)
    filter='
      ([.bar.layout[]?[]? | select(.id == "omext.start")][0] // {"id": "omext.start"}) as $start
      | if ([.bar.layout[]?[]? | select(.id == "omarchy.menu")] | length) == 0 then .
        else .bar.layout |= with_entries(.value |= map(select(.id != "omext.start")))
           | .bar.layout |= with_entries(.value |= map(if .id == "omarchy.menu" then $start else . end))
        end'
    ;;
  give)
    filter='
      if ([.bar.layout[]?[]? | select(.id == "omarchy.menu")] | length) > 0 then .
      elif ([.bar.layout[]?[]? | select(.id == "omext.start")] | length) > 0 then
        .bar.layout |= with_entries(.value |= map(if .id == "omext.start" then {"id": "omarchy.menu"}, . else . end))
      else .bar.layout.left = [{"id": "omarchy.menu"}] + (.bar.layout.left // [])
      end'
    ;;
  *)
    echo "usage: ${0##*/} take|give" >&2
    exit 2
    ;;
esac

tmp=$conf.omext-start.tmp
jq "$filter" "$conf" > "$tmp" && [[ -s $tmp ]] && ! cmp -s "$tmp" "$conf" && cat "$tmp" > "$conf"
rm -f "$tmp"
