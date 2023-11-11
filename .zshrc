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
command -v stern >/dev/null && . <(stern --completion zsh)
command -v kubebuilder >/dev/null && . <(kubebuilder completion zsh)
eval "$(starship init zsh)"


export GOPATH=$HOME/go
export GOROOT="$(brew --prefix golang)/libexec"
export PATH="$PATH:${GOPATH}/bin:${GOROOT}/bin"
export PATH="$(brew --prefix)/opt/gnu-sed/libexec/gnubin:$PATH"