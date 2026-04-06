export PS1='ghostty$ '
export TERM="${TERM:-xterm-256color}"
export COLORTERM="${COLORTERM:-truecolor}"
export CLICOLOR=1

shopt -s checkwinsize
shopt -s expand_aliases

if ls --color=auto >/dev/null 2>&1; then
  alias ls='ls --color=auto'
elif ls -G >/dev/null 2>&1; then
  alias ls='ls -G'
fi
