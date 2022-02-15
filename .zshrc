autoload -Uz compinit
compinit -i

source ~/.zsh/aliases/.aliases
source ~/.zsh/functions/.functions
source ~/.private.zshenv
source ~/.zsh/exports/.exports

bindkey -s '^e' 'vim $(fzf)\n'
bindkey '\e[A' history-beginning-search-backward
bindkey '\e[B' history-beginning-search-forward

command -v flux >/dev/null && . <(flux completion zsh)
eval "$(starship init zsh)"
