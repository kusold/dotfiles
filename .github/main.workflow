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
  uses = "docker://koalaman/shellcheck"
  args = "shellcheck .yadm/bootstraps/*.sh"
}
