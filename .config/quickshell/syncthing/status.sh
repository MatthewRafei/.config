#!/bin/sh
# One JSON line for Syncthing.qml, from Syncthing's local REST API:
#   { running, completion, needBytes, folders: [{ id, label, state, paused, errors }],
#     devices: [{ name, connected, paused }], errors }
# Prints {"running":false} when Syncthing isn't answering.
conf="${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml"
[ -f "$conf" ] || conf="$HOME/.config/syncthing/config.xml"
key=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$conf" 2>/dev/null | head -n 1)
gui=$(sed -n '/<gui /,/<\/gui>/s:.*<address>\(.*\)</address>.*:\1:p' "$conf" 2>/dev/null | head -n 1)
base="http://${gui:-127.0.0.1:8384}/rest"
api() { curl -sf -m 3 -H "X-API-Key: $key" "$base/$1"; }

me=$(api system/status | jq -r .myID) || { echo '{"running":false}'; exit 0; }
folders=$(api config/folders) || { echo '{"running":false}'; exit 0; }
states=$(for id in $(echo "$folders" | jq -r '.[].id'); do
    api "db/status?folder=$id" | jq -c --arg id "$id" '{id: $id, state: .state, errors: ((.errors // 0) + (.pullErrors // 0))}'
done | jq -s .)

jq -nc --arg me "$me" \
    --argjson folders "$folders" --argjson states "$states" \
    --argjson devices "$(api config/devices)" --argjson conns "$(api system/connections)" \
    --argjson comp "$(api db/completion)" --argjson errs "$(api system/error)" '
    {
        running: true,
        completion: $comp.completion,
        needBytes: $comp.needBytes,
        folders: [$folders[] | . as $f | ($states[] | select(.id == $f.id)) as $s
                  | { id: .id, label: (.label // .id), paused: .paused,
                      state: $s.state, errors: $s.errors }],
        devices: [$devices[] | select(.deviceID != $me)
                  | { name: .name, paused: .paused,
                      connected: ($conns.connections[.deviceID].connected // false) }],
        errors: (($errs.errors // []) | length)
    }'
