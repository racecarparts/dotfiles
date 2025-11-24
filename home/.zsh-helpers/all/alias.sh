# alias ll='ls -aGop'
# alias ls='ls -F'
alias ls='lsd'

alias l='lsd -l'
alias la='lsd -a'
alias ll='lsd -la'
alias lt='lsd --tree'

alias python='python3'
alias pip='pip3'

alias ccm='ccmonitor --theme dark --plan pro'
alias ccuser='jq -r ".oauthAccount.emailAddress // \"Not logged in\"" ~/.claude.json 2>/dev/null || echo "Claude not configured"'