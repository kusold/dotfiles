set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim'
Plugin 'puppetlabs/puppet-syntax-vim'
Plugin 'tpope/vim-fugitive'
Plugin 'kien/ctrlp.vim'
Plugin 'mhinz/vim-signify'
" All of your Plugins must be added before the following line
call vundle#end()            " required
" Brief help
" :PluginList          - list configured plugins
" :PluginInstall(!)    - install (update) plugins
" :PluginSearch(!) foo - search (or refresh cache first) for foo
" :PluginClean(!)      - confirm (or auto-approve) removal of unused plugins
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line

" Syntax highlighting
syntax on

" Loading the indent file for specific file types
filetype plugin indent on

set nu " Line numbering on
set showmatch " Show matching brackets/paranthesis

" Signify
let g:signify_vcs_list = ['git'] " Limit support to git for speed. Why would I use anything else?
let g:signify_mapping_next_hunk = '<leader>gj' " Go to next hunk
let g:signify_mapping_prev_hunk = '<leader>gk' " Go to previous hunk
