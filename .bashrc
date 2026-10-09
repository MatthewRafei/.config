# Paste this at the end of your ~/.bashrc
#PROMPT_ALTERNATIVE() {
#    local EXIT="$?"
#    local Reset="\[\e[0m\]"
#    local Cyan="\[\e[36m\]"
#    local Green="\[\e[32m\]"
#    local Red="\[\e[31m\]"
#    local Gray="\[\e[90m\]"
#
#    # Arrow changes color based on success/failure
#    local ArrowColor="$Green"
#    if [ $EXIT -ne 0 ]; then
#        ArrowColor="$Red"
#    fi
#
#    PS1="\n${Gray}┌─[${Cyan}\w${Gray}]\n└─${ArrowColor}❯${Reset} "
#}
#PROMPT_COMMAND=PROMPT_ALTERNATIVE


PATH="$HOME/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="$HOME/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"$HOME/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=$HOME/perl5"; export PERL_MM_OPT;

eval "$(starship init bash)"
export PATH="$HOME/.local/bin:$PATH"

# Emacs is the editor: a frame of the running daemon, in this terminal
# (starts the daemon if it isn't running). `emacs FILE` opens a window.
export EDITOR="emacsclient -t -a ''"
export VISUAL="$EDITOR"

# dotfiles: bare git repo in ~/.dotfiles tracking configs in place
#   dots status | dots add <file> | dots commit -m "..." | dots log
alias dots='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

# Hyprland resizes a new terminal ~50ms after it opens. Starship's first
# prompt would be drawn at the old width and its right-aligned clock would
# wrap ("PM" on its own line), so wait for that resize first. `wait` returns
# as soon as the trapped SIGWINCH arrives; 150ms at most otherwise. niri sizes
# windows before their first frame, so it doesn't need (or pay for) this.
if [[ $- == *i* && -n $ALACRITTY_WINDOW_ID && -n $HYPRLAND_INSTANCE_SIGNATURE && -z $_TERM_SETTLED ]]; then
    export _TERM_SETTLED=1
    set +m                                  # no "[1]+ Terminated" job notice
    trap : WINCH
    sleep 0.15 & _settle=$!
    wait $_settle 2>/dev/null
    kill $_settle 2>/dev/null; wait $_settle 2>/dev/null
    trap - WINCH
    set -m
    unset _settle
fi

# Claude Code: `claude` starts a kept session that survives closing the
# terminal (quickshell agents module; `command claude` for a plain one)
[ -r ~/.config/quickshell/modules/agents/claude.bash ] && . ~/.config/quickshell/modules/agents/claude.bash
