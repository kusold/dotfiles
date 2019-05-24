workflow "Lint" {
  resolves = [
    "Lint vimrc",
    "ShellCheck",
  ]
  on = "push"
}

action "Lint vimrc" {
  uses = "docker://upstreamable/vint"
  args = "vint --color --style .vimrc"
}

action "ShellCheck" {
  uses = "docker://jess/shellcheck"
  args = "sh -c ./.github/shellcheck_all.sh"
}
