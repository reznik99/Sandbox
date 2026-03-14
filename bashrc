# lsd replaces ls
alias ll='lsd -l'
alias la='lsd -la'
alias lt='lsd --tree'

# fzf keybindings and completion
eval "$(fzf --bash)"

# Prompt
PS1='\[\e[1;33m\][sandbox]\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] \$ '
