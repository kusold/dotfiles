if ! grep -q $(which zsh) /etc/shells; then
  echo "Setting default shell to $(which zsh)"
  sudo sh -c "echo $(which zsh) >> /etc/shells"
  chsh -s $(which zsh)
fi
