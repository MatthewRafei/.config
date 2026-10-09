# Sourced from ~/.bashrc. `claude` typed in a terminal starts a kept session:
# it runs in the agents module's private tmux server (tmux.conf), so closing
# the terminal only detaches it, busy or idle, and the bar's agents panel
# opens it again. When claude exits, the session and the tmux client end
# and you're back at the prompt.
#
# Falls back to plain claude for subcommands, -p / --help / --version,
# inside tmux already, without a terminal, without tmux, with the agents
# module switched off, or with CLAUDE_NO_KEEP=1. `command claude` skips it too.
claude() {
    local conf="$HOME/.config/quickshell/modules/agents/tmux.conf"
    local mods="$HOME/.local/share/quickshell/modules.json"
    if [[ -n $TMUX || -n $CLAUDE_NO_KEEP || ! -t 0 || ! -t 1 || ! -r $conf ]] \
        || ! command -v tmux >/dev/null \
        || { [[ -r $mods ]] && grep -Eq '"agents"[[:space:]]*:[[:space:]]*false' "$mods"; }; then
        command claude "$@"
        return
    fi
    case $1 in
        agents|attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|plugin|plugins|purge \
        |respawn|rm|setup-token|stop|kill|ultrareview|update|upgrade|daemon)
            command claude "$@"
            return ;;
    esac
    local a
    for a; do
        case $a in -p|--print|-h|--help|-v|--version) command claude "$@"; return ;; esac
    done
    # same naming as sessions started from the panel: cc-<folder>-<random>
    local base=${PWD##*/}
    base=${base//[^A-Za-z0-9_-]/}
    local name="cc-${base:0:20}"
    [[ $name == cc- ]] && name=cc-home
    name+="-$(printf '%04x' $RANDOM)"
    # the tmux server may have been started by quickshell (niri's PATH and
    # environment): hand this shell's exported variables to the session
    local envs=() n
    while read -r n; do
        case $n in PWD|OLDPWD|SHLVL|_|TMUX|TMUX_PANE) continue ;; esac
        envs+=(-e "$n=${!n}")
    done < <(compgen -e)
    tmux -L claude -f "$conf" new-session "${envs[@]}" -s "$name" -c "$PWD" -- "$(type -P claude)" "$@"
}
