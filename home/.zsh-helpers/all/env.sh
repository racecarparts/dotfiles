export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

[[ -f "$HOME/.env.secrets" ]] && source "$HOME/.env.secrets"
