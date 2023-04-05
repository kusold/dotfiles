if has('nvim')
    let vim_plug_path = $XDG_DATA_HOME . '/nvim/site/autoload/plug.vim'
else
    let vim_plug_path = '~/.vim/autoload/plug.vim'
endif

if empty(glob(vim_plug_path))
  silent execute '!curl -fLo ' . vim_plug_path . ' --create-dirs
        \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  augroup plug_install
      au!
      autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
  augroup END
endif
