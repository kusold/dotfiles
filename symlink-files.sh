#!/bin/bash

ln -sf ~/dotfiles/gitconfig ~/.gitconfig
ln -sf ~/dotfiles/ansiweatherrc ~/.ansiweatherrc
ln -sf ~/dotfiles/tmux.conf ~/.tmux.conf
ln -sf ~/dotfiles/rvmrc ~/.rvmrc
ln -sf ~/dotfiles/vimrc ~/.vimrc
ln -sf ~/dotfiles/ssh_rc ~/.ssh/rc
ln -sf ~/dotfiles/xinitrc ~/.ssh/.xinitrc

# Prevent recursive directory creation (vim/vim/vim)
VIM_PATH=`pwd`/vim
if ! [[ `ls -al $HOME | grep $VIM_PATH$` ]]; then
  ln -sf ~/dotfiles/vim ~/.vim
fi

# Prevent recursive directory creation (vim/vim/vim)
TMUX_PATH=`pwd`/tmux
if ! [[ `ls -al $HOME | grep $TMUX_PATH$` ]]; then
  ln -sf ~/dotfiles/tmux ~/.tmux
fi

FONTS_PATH=`pwd`/fonts
if ! [[ `ls -al $HOME | grep $FONTS_PATH$` ]]; then
  ln -sf ~/dotfiles/fonts ~/.fonts
fi
FONTS_CONF_PATH=`pwd`/fonts.conf.d
if ! [[ `ls -al $HOME | grep $FONTS_CONF_PATH$` ]]; then
  ln -sf ~/dotfiles/fonts.conf.d ~/.config/fontconfig/conf.d
fi
PREZTO_PATH=`pwd`/prezto
if ! [[ `ls -al $HOME | grep $PREZTO_PATH$` ]]; then
  ln -sf ~/dotfiles/prezto ~/.zprezto
fi

# Pretzo (oh-my-zsh fork) setup 
ln -sf ~/dotfiles/zsh-configs/zlogin ~/.zlogin
ln -sf ~/dotfiles/zsh-configs/zlogout ~/.zlogout
ln -sf ~/dotfiles/zsh-configs/zpreztorc ~/.zpreztorc
ln -sf ~/dotfiles/zsh-configs/zprofile ~/.zprofile
ln -sf ~/dotfiles/zsh-configs/zshenv ~/.zshenv
ln -sf ~/dotfiles/zsh-configs/zshrc ~/.zshrc
#sudo ln -sf ~/dotfiles/mySystemWideVariables.sh /etc/profile.d/kusoldSystemWideVariables.sh

