#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# starship prompt (themed to match the bar/ghostty); skipped if not installed
command -v starship >/dev/null && eval "$(starship init bash)"

# default editor (used by starship config, git, sudoedit, ...)
export EDITOR=nano
export VISUAL=nano
export PATH="$HOME/.local/bin:$PATH"

# colours that follow the wallpaper: ghostty palette slots (6 = primary accent, 10 = secondary)
export BAT_THEME=ansi
export FZF_DEFAULT_OPTS="--color=fg:7,hl:6,fg+:15,bg+:-1,hl+:6,info:8,prompt:6,pointer:10,marker:10,spinner:10,header:8,border:8,gutter:-1 --pointer=▌ --marker=▌"

# fastfetch with the round avatar as logo, but only in a local Ghostty (image protocol; over SSH
# or in other terminals the themed Arch logo from the config)
fastfetch() {
	if [[ $TERM == xterm-ghostty && -z $SSH_CONNECTION && -f ~/.config/theme/avatar.png ]]; then
		command fastfetch --logo-type kitty-direct --logo ~/.config/theme/avatar.png \
			--logo-width 20 --logo-height 10 "$@"
	else
		command fastfetch "$@"
	fi
}
