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


PATH="/home/malac0da/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="/home/malac0da/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/home/malac0da/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/home/malac0da/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/home/malac0da/perl5"; export PERL_MM_OPT;

eval "$(starship init bash)"
export PATH="$HOME/.local/bin:$PATH"

# dotfiles: bare git repo in ~/.dotfiles tracking configs in place
#   dots status | dots add <file> | dots commit -m "..." | dots log
alias dots='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
