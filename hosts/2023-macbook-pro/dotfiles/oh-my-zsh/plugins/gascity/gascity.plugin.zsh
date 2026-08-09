# oh-my-zsh's git plugin aliases gc to `git commit -v`, which shadows the
# gascity binary. gascity cannot yield the name: it bakes `gc` into the hook
# commands it injects into agent panes, and its completion registers as
# `#compdef gc`. This plugin must therefore be listed AFTER git in the
# oh-my-zsh plugins array — they are sourced in array order, so loading first
# would just let the git plugin recreate the alias.
# https://docs.gascity.com/getting-started/troubleshooting#oh-my-zsh-git-plugin-hides-gc
unalias gc 2>/dev/null

alias gci='git commit -v'
