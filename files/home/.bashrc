#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# starship prompt (themed to match waybar/ghostty); skipped if not installed
command -v starship >/dev/null && eval "$(starship init bash)"

# default editor (used by starship config, git, sudoedit, ...)
export EDITOR=nano
export VISUAL=nano
export PATH="$HOME/.local/bin:$PATH"
