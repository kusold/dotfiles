workflow "Lint" {
  resolves = ["Lint vimrc"]
  on = "push"
}

action "Lint vimrc" {
  uses = "docker://upstreamable/vint"
  args = "--color --style .vimrc"
}
