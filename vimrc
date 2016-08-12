set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim' "Package manager
Plugin 'pangloss/vim-javascript' "Better Javascript syntax highlighting (Required by react)
Plugin 'mxw/vim-jsx' "JSX support (React)
Plugin 'kchmck/vim-coffee-script' "Coffeescript support
Plugin 'puppetlabs/puppet-syntax-vim' "Puppet support
Plugin 'saltstack/salt-vim' "Salt Syntax Support
Plugin 'digitaltoad/vim-jade' "Jade language syntax highlighting
Plugin 'ap/vim-css-color' "Highlights colors in css files
Plugin 'tpope/vim-fugitive' "Git in vim
Plugin 'kien/ctrlp.vim' "Ctrl-P <filename> to open
Plugin 'mhinz/vim-signify' "Display which lines have changed for git
Plugin 'mattn/emmet-vim' "Shortcuts to generate HTML
Plugin 'tpope/vim-dispatch' "Asynchronous command running. Useful for builds/tests
Plugin 'tpope/vim-sleuth' "Match indentation style
Plugin 'tpope/vim-surround' "Easy keybindings for surrounding things in pairs
Plugin 'tpope/vim-repeat' "Enable plugin bindings (such as vim-surround) to be repeated with `.`
Plugin 'fatih/vim-go'	"Run :GoInstallBinaries to pull down dependencies.
                        "Requires modifying gitconfig https rewrite.
Plugin 'scrooloose/nerdtree' "File Browser
Plugin 'jistr/vim-nerdtree-tabs' "Same nerdtree in every file
Plugin 'scrooloose/syntastic' "Display where errors and warnings occur
Plugin 'jaxbot/syntastic-react' "Syntax checking for React
Plugin 'Raimondi/delimitMate' " Autoclose quotes and groupings ()
Plugin 'bling/vim-airline' "Style the status bar
Plugin 'Shougo/neocomplete.vim' "Auto word completions
Plugin 'janko-m/vim-test' "Execute tests from inside vim
Plugin 'tmux-plugins/vim-tmux-focus-events' "makes tmux + vim work with focus events
Plugin 'tpope/vim-unimpaired' "provides several pairs of bracket maps.
Plugin 'wakatime/vim-wakatime' "Collects stats on programming
Plugin 'Konfekt/FastFold' "Allow syntax folding without constant recaclulation

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

set background=dark " Dark background friendly
set number " Line numbering on
set showmatch " Show matching brackets/paranthesis
set tabstop=4 "Tabs take up 4 spaces
"set shiftwidth=2
"set softtabstop=2
set ruler " Display location in file
set showcmd "Show command in the last line of the screen
set incsearch "Search as you type. Return to original location if canceled.
"set mouse=a "Enable the mouse use in all modes
set ignorecase "case insensitive searching
set smartcase "if search isn't all lowercase, casesensitive search
set backspace=indent,eol,start "make backspace behave like normal"

" Display characters to symbolize whitespace
"set list
set listchars=tab:▸\ ,eol:¬

nnoremap <silent> <leader>> :vertical resize 123<CR> "Automatically resize split to fit 120 chars

function! SetupCommandAlias(from, to)
  exec 'cnoreabbrev <expr> '.a:from
  \ .' ((getcmdtype() is# ":" && getcmdline() is# "'.a:from.'")'
  \ .'? ("'.a:to.'") : ("'.a:from.'"))'
endfunction
call SetupCommandAlias("Q", "q")
call SetupCommandAlias("W", "w")

" ----- background highlight the character if line length goes over 120 -----
highlight OverLengthIndiator ctermbg=darkyellow
call matchadd('OverLengthIndiator', '\%121v', 100)

autocmd BufNewFile,BufFilePre,BufRead *.md set filetype=markdown " .md == markdown. .md != modula-2

" ----- mhinz/signify settings -----
let g:signify_vcs_list = ['git'] " Limit support to git for speed. Why would I use anything else?
let g:signify_mapping_next_hunk = '<leader>gj' " Go to next hunk
let g:signify_mapping_prev_hunk = '<leader>gk' " Go to previous hunk

" ----- scrooloose/nerdtree and justr/vim-nerdtree-tabs settings -----
" Open/close NERDTree Tabs (explorer tree) with \e
nmap <silent> <leader>e :NERDTreeTabsToggle<CR>
" To have NERDTree always open on startup. 0 = disabled
let g:nerdtree_tabs_open_on_console_startup = 0

" ----- scrooloose/syntastic settings -----
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_error_symbol = '✘'
let g:syntastic_warning_symbol = "▲"
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_loc_list_height=5

augroup mySyntastic
  au!
  au FileType tex let b:syntastic_mode = "passive"
augroup END

let g:syntastic_javascript_checkers = ['eslint'] "Use eslint for syntax checking
let g:syntastic_go_checkers = ['go', 'gofmt', 'golint', 'govet', 'errcheck']
"let g:syntastic_mode_map = { 'mode': 'active', 'passive_filetypes': ['go'] }
let g:syntastic_make_checkers = ['gnumake']

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
let g:airline#extensions#tabline#enabled = 1 " Enable the list of buffers
let g:airline#extensions#tabline#fnamemod = ':t' " Show just the filename

" ----- mattn/emmet-vim settings -----
"let g:user_emmet_install_global = 0
"autocmd FileType html,css,tpl EmmetInstall "Only enable for html,css,tpl files

" ----- pangloss/vim-javascript -----
let g:javascript_conceal_function       = "ƒ"
let g:javascript_conceal_null           = "ø"
let g:javascript_conceal_this           = "@"
let g:javascript_conceal_return         = "⇚"
let g:javascript_conceal_undefined      = "¿"
let g:javascript_conceal_NaN            = "ℕ"
let g:javascript_conceal_prototype      = "¶"
let g:javascript_conceal_static         = "•"
let g:javascript_conceal_super          = "Ω"
let g:javascript_conceal_arrow_function = "⇒"

" ----- mxw/vim-jsx -----
let g:jsx_ext_required = 0


" ----- janko-m/vim-test -----
nmap <silent> <leader>t :TestNearest<CR>
nmap <silent> <leader>T :TestFile<CR>
nmap <silent> <leader>a :TestSuite<CR>
nmap <silent> <leader>l :TestLast<CR>
nmap <silent> <leader>g :TestVisit<CR>

" make test commands execute using dispatch.vim
let test#strategy = "dispatch"

" Set the NODE_ENV correctly for tests
let test#javascript#mocha#executable = 'NODE_ENV=test ' . test#javascript#mocha#executable()

" ----- Konfekt/FastFold settings -----


" ----- Shougo/neocomplete.vim settings -----
let g:acp_enableAtStartup = 0 " Disable AutoComplPop.
let g:neocomplete#enable_at_startup = 1 " Use neocomplete.
let g:neocomplete#enable_smart_case = 1 " Use smartcase.
let g:neocomplete#sources#syntax#min_keyword_length = 3 " Set minimum syntax keyword length.
let g:neocomplete#lock_buffer_name_pattern = '\*ku\*'

" Define dictionary.
let g:neocomplete#sources#dictionary#dictionaries = {
    \ 'default' : '',
    \ 'vimshell' : $HOME.'/.vimshell_hist',
    \ 'scheme' : $HOME.'/.gosh_completions'
        \ }

" Define keyword.
if !exists('g:neocomplete#keyword_patterns')
    let g:neocomplete#keyword_patterns = {}
endif
let g:neocomplete#keyword_patterns['default'] = '\h\w*'

" Plugin key-mappings.
inoremap <expr><C-g>     neocomplete#undo_completion()
inoremap <expr><C-l>     neocomplete#complete_common_string()

" Recommended key-mappings.
" <CR>: close popup and save indent.

" ---Play niceley with delimitMate
"inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
imap <expr> <CR> pumvisible() ? neocomplete#close_popup() . "\<CR>" : "<Plug>delimitMateCR"
function! s:my_cr_function()
  return neocomplete#close_popup() . "\<CR>"
  " For no inserting <CR> key.
  " return pumvisible() ? neocomplete#close_popup() : "\<CR>
endfunction
" <TAB>: completion.
inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
" <C-h>, <BS>: close popup and delete backword char.
inoremap <expr><C-h> neocomplete#smart_close_popup()."\<C-h>"
inoremap <expr><BS> neocomplete#smart_close_popup()."\<C-h>"
inoremap <expr><C-y>  neocomplete#close_popup()
inoremap <expr><C-e>  neocomplete#cancel_popup()
" Close popup by <Space>.
"inoremap <expr><Space> pumvisible() ? neocomplete#close_popup() : "\<Space>"

" For cursor moving in insert mode(Not recommended)
"inoremap <expr><Left>  neocomplete#close_popup() . "\<Left>"
"inoremap <expr><Right> neocomplete#close_popup() . "\<Right>"
"inoremap <expr><Up>    neocomplete#close_popup() . "\<Up>"
"inoremap <expr><Down>  neocomplete#close_popup() . "\<Down>"
" Or set this.
"let g:neocomplete#enable_cursor_hold_i = 1

" AutoComplPop like behavior.
"let g:neocomplete#enable_auto_select = 1

" Shell like behavior(not recommended).
"set completeopt+=longest
"let g:neocomplete#enable_auto_select = 1
"let g:neocomplete#disable_auto_complete = 1
"inoremap <expr><TAB>  pumvisible() ? "\<Down>" : "\<C-x>\<C-u>"

" Enable omni completion.
autocmd FileType css setlocal omnifunc=csscomplete#CompleteCSS
autocmd FileType html,markdown setlocal omnifunc=htmlcomplete#CompleteTags
autocmd FileType javascript setlocal omnifunc=javascriptcomplete#CompleteJS
autocmd FileType python setlocal omnifunc=pythoncomplete#Complete
autocmd FileType xml setlocal omnifunc=xmlcomplete#CompleteTags

" Enable heavy omni completion.
if !exists('g:neocomplete#sources#omni#input_patterns')
  let g:neocomplete#sources#omni#input_patterns = {}
endif
"let g:neocomplete#sources#omni#input_patterns.php = '[^. \t]->\h\w*\|\h\w*::'
"let g:neocomplete#sources#omni#input_patterns.c = '[^.[:digit:] *\t]\%(\.\|->\)'
"let g:neocomplete#sources#omni#input_patterns.cpp = '[^.[:digit:] *\t]\%(\.\|->\)\|\h\w*::'

" For perlomni.vim setting.
" https://github.com/c9s/perlomni.vim
let g:neocomplete#sources#omni#input_patterns.perl = '\h\w*->\h\w*\|\h\w*::'

