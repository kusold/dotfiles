set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim' "Package manager
Plugin 'puppetlabs/puppet-syntax-vim' "Puppet support
Plugin 'digitaltoad/vim-jade' "Jade language syntax highlighting
Plugin 'skammer/vim-css-color' "Highlights colors in css files
Plugin 'tpope/vim-fugitive' "Git in vim
Plugin 'kien/ctrlp.vim' "Ctrl-P <filename> to open
Plugin 'mhinz/vim-signify' "Display which lines have changed for git
Plugin 'mattn/emmet-vim' "Shortcuts to generate HTML
Plugin 'tpope/vim-sleuth' "Match indentation style
Plugin 'fatih/vim-go'	"Run :GoInstallBinaries to pull down dependencies.
						"Requires modifying gitconfig https rewrite.
Plugin 'scrooloose/nerdtree' "File Browser
Plugin 'jistr/vim-nerdtree-tabs' "Same nerdtree in every file
Plugin 'scrooloose/syntastic' "Display where errors and warnings occur
Plugin 'Raimondi/delimitMate' " Autoclose quotes and groupings ()
Plugin 'bling/vim-airline'

"Plugin 'ciaranm/detectindent'
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

set number " Line numbering on
set showmatch " Show matching brackets/paranthesis
set tabstop=4 "Tabs take up 4 spaces
"set shiftwidth=2
"set softtabstop=2
set ruler " Display location in file
set showcmd "Show command in the last line of the screen
set incsearch "Search as you type. Return to original location if canceled.
set mouse=a "Enable the mouse use in all modes

" ----- background highlight the character if line length goes over 120 -----
highlight OverLengthIndiator ctermbg=darkyellow
call matchadd('OverLengthIndiator', '\%121v', 100)

" ----- mhinz/signify settings -----
let g:signify_vcs_list = ['git'] " Limit support to git for speed. Why would I use anything else?
let g:signify_mapping_next_hunk = '<leader>gj' " Go to next hunk
let g:signify_mapping_prev_hunk = '<leader>gk' " Go to previous hunk

" ----- scrooloose/nerdtree and justr/vim-nerdtree-tabs settings -----
" Open/close NERDTree Tabs with \t
nmap <silent> <leader>t :NERDTreeTabsToggle<CR>
" To have NERDTree always open on startup. 0 = disabled
let g:nerdtree_tabs_open_on_console_startup = 0

" ----- scrooloose/syntastic settings -----
let g:syntastic_error_symbol = '✘'
let g:syntastic_warning_symbol = "▲"
augroup mySyntastic
	au!
	au FileType tex let b:syntastic_mode = "passive"
augroup END

" ----- Raimondi/delimitMate settings -----
let delimitMate_expand_cr = 1
augroup mydelimitMate
	au!
	au FileType markdown let b:delimitMate_nesting_quotes = ["`"]
	au FileType tex let b:delimitMate_quotes = ""
	au FileType tex let b:delimitMate_matchpairs = "(:),[:],{:},`:'"
    au FileType python let b:delimitMate_nesting_quotes = ['"', "'"]
augroup END

" ----- faith/vim-go settings -----
let g:go_fmt_command = "goimports" "Use goimports instead of gofmt to insert imports
"\s to list interfaces implemented by the type
au FileType go nmap <Leader>s <Plug>(go-implements)
"\i to show type info
au FileType go nmap <Leader>i <Plug>(go-info)

" ----- bling/vim-airline settings -----
set laststatus=2
set timeoutlen=1000
set ttimeoutlen=50
let g:airline_powerline_fonts = 1

" ----- mattn/emmet-vim settings -----
"let g:user_emmet_install_global = 0
"autocmd FileType html,css,tpl EmmetInstall "Only enable for html,css,tpl files
