#!/bin/bash

ln -sf ~/dotfiles/gitconfig ~/.gitconfig
ln -sf ~/dotfiles/ansiweatherrc ~/.ansiweatherrc
ln -sf ~/dotfiles/tmux.conf ~/.tmux.conf
ln -sf ~/dotfiles/rvmrc ~/.rvmrc
ln -sf ~/dotfiles/vimrc ~/.vimrc
ln -sf ~/dotfiles/vim ~/.vim
ln -sf ~/dotfiles/ssh_rc ~/.ssh/rc

# Pretzo (oh-my-zsh fork) setup 
ln -sf ~/dotfiles/zsh-configs/zlogin ~/.zlogin
ln -sf ~/dotfiles/zsh-configs/zlogout ~/.zlogout
ln -sf ~/dotfiles/zsh-configs/zpreztorc ~/.zpreztorc
ln -sf ~/dotfiles/zsh-configs/zprofile ~/.zprofile
ln -sf ~/dotfiles/zsh-configs/zshenv ~/.zshenv
ln -sf ~/dotfiles/zsh-configs/zshrc ~/.zshrc
ln -sf ~/dotfiles/prezto ~/.zprezto
sudo ln -sf ~/dotfiles/mySystemWideVariables.sh /etc/profile.d/kusoldSystemWideVariables.sh

