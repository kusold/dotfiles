" Refactored vimrc start

"│-v-1 │ to-do's
"└─────┴─────────
  " TODO Move all settings into folds
  " TODO Convert most plugins to lazy load
  " TODO evaluate if all plugins are necessary
  " TODO expand on plugin descriptions
  " TODO investigate https://github.com/reedes/vim-thematic
  " TODO https://github.com/mbbill/undotree
  " TODO https://github.com/godlygeek/tabular

"│-v-1 │ initiliaze
"└─┬───┴─┬────────────────
  "│-v-2 │ compatibility settings
  "└─────┴─────────
    " Disable vi compatibility settings
    set nocompatible

    "For that which __requires_utf_8:
    set encoding=utf8

  "│-v-2 │ filetype settings
  "└─────┴─────────
    " Enable filetype detection
    " Enable loading of filetype plugins
    " Enable loading of filetype indents
    filetype plugin indent on

  "│-v-2 │ leader key settings
  "└─────┴─────────
    " Set the leader key to \
    let mapleader = "\\"

"│-v-1 │ plugin settings
"└─┬───┴─┬────────────────
  "│-v-2 │ junegunn/vim-plug (plugin manager)
  "└─┬───┴─┬────────────────
    "│-v-3 │ plugin manager init
    "└─────┴─────────
      " Load vim-plug
      call plug#begin('~/.vim/plugged')
    "│-v-3 │ plugin list
    "└─┬───┴─┬────────────────
      "│-v-4 │ appearance
      "└─────┴─────────
        " Style the status/tabline
        Plug 'bling/vim-airline'

        " Dracula color schme
        Plug 'dracula/vim', { 'as': 'dracula' }

        "Display which lines have changed for git
        Plug 'mhinz/vim-signify'

        " Adds filetype glyphs (icons) to NerdTree and other plugins
        " Requires special fonts
        Plug 'ryanoasis/vim-devicons'

        "Highlight devicons in nerdtree
        Plug 'tiagofumo/vim-nerdtree-syntax-highlight', { 'on': 'NERDTreeTabsToggle' }

      "│-v-4 │ performance
      "└─────┴─────────
        "Allow syntax folding without constant recaclulation
        Plug 'Konfekt/FastFold'

        "Faster grep for code
        Plug 'mileszs/ack.vim', {'on': 'Ack!'}

        "Asyncronous job running (Make and Linting)
        Plug 'neomake/neomake'

        "Asynchronous command running. Useful for builds/tests
        Plug 'tpope/vim-dispatch'

      "│-v-4 │ ide
      "└─────┴─────────
        " Autocompletions
        Plug 'Shougo/neocomplete.vim'

        " File Browser
        Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeTabsToggle' }

         "Same nerdtree in every file
        Plug 'jistr/vim-nerdtree-tabs', { 'on': 'NERDTreeTabsToggle' }

        "Ctrl-P <filename> to open
        Plug 'ctrlpvim/ctrlp.vim'

        "Execute tests from inside vim
        Plug 'janko-m/vim-test'

        "Display ctags in a tagbar
        Plug 'majutsushi/tagbar', { 'on': 'TagbarToggle' }

        "Disaply fancy start screen on start
        Plug 'mhinz/vim-startify'

        "Git in vim
        Plug 'tpope/vim-fugitive'

        Plug 'vim-syntastic/syntastic' "Display where errors and warnings occur

      "│-v-4 │ editing
      "└─────┴─────────
        " Autoclose quotes and groupings ()
        Plug 'Raimondi/delimitMate'

        "Easy keybindings for surrounding things in pairs
        Plug 'tpope/vim-surround'

        "provides several pairs of bracket maps.
        Plug 'tpope/vim-unimpaired'

        "Enable plugin bindings (such as vim-surround) to be repeated with `.`
        Plug 'tpope/vim-repeat'

        "Match indentation style
        Plug 'tpope/vim-sleuth'

      "│-v-4 │ language specific
      "└─────┴─────────
        " Shows a rough representation of color codes
        Plug 'ap/vim-css-color', {'for': ['css', 'scss', 'sass']}

        " Jade language syntax highlighting
        Plug 'digitaltoad/vim-jade', {'for': 'jade'}

        "Better Javascript syntax highlighting (Required by react)
        Plug 'pangloss/vim-javascript', {'for': ['javascript', 'jsx']}

        "Run :GoInstallBinaries to pull down dependencies.
        "Requires modifying gitconfig https rewrite.
        Plug 'fatih/vim-go', { 'do': ':GoInstallBinaries', 'for': 'go' }

        "Syntax checking for React
        Plug 'jaxbot/syntastic-react', {'for': 'jsx'}

        "JSX support (React)
        Plug 'mxw/vim-jsx', {'for': 'jsx'}

      "│-v-4 │ miscellaneous
      "└─────┴─────────
        "makes tmux + vim work with focus events
        Plug 'tmux-plugins/vim-tmux-focus-events'

        "Collects stats on programming
        Plug 'wakatime/vim-wakatime'

    "│-v-3 │ plugin manager deinit
    "└─────┴─────────
      call plug#end()

  "│-v-2 │ ack - mileszs/ack.vim
  "└─────┴─────────
    " if silver surfer is installed, use that instead
    if executable('ag')
      let g:ackprg = 'ag --vimgrep'
    endif

    " Don't automatically jump to the first result
    cnoreabbrev Ack Ack!
    nnoremap <Leader>a :Ack!<Space>

  "│-v-2 │ airline - bling/vim-airline
  "└─────┴─────────
    set laststatus=2
    set timeoutlen=1000
    set ttimeoutlen=50
    let g:airline_powerline_fonts = 1
    let g:airline#extensions#tabline#enabled = 1 " Enable the list of buffers
    let g:airline#extensions#tabline#fnamemod = ':t' " Show just the filename

  "│-v-2 │ ctrlp - ctrlpvim/ctrlp.vim
  "└─────┴─────────
    " The Silver Searcher
    if executable('ag')
      " Use ag in CtrlP for listing files. Lightning fast and respects .gitignore
      let g:ctrlp_user_command = 'ag %s -l --nocolor -g ""'

      " ag is fast enough that CtrlP doesn't need to cache
      let g:ctrlp_use_caching = 0
    endif

  "│-v-2 │ delimitMate - Raimondi/delimitMate
  "└─────┴─────────
    let delimitMate_expand_cr = 1
    augroup mydelimitMate
      au!
      au FileType markdown let b:delimitMate_nesting_quotes = ["`"]
      au FileType tex let b:delimitMate_quotes = ""
      au FileType tex let b:delimitMate_matchpairs = "(:),[:],{:},`:'"
      au FileType python let b:delimitMate_nesting_quotes = ['"', "'"]
    augroup END

  "│-v-2 │ emmet - mattn/emmet-vim
  "└─────┴─────────
    "let g:user_emmet_install_global = 0
    "autocmd FileType html,css,tpl EmmetInstall "Only enable for html,css,tpl files

  "│-v-2 │ fastfold - Konfekt/FastFold
  "└─────┴─────────
  "│-v-2 │ go - faith/vim-go
  "└─────┴─────────
    "let g:go_highlight_functions = 1
    "let g:go_highlight_methods = 1
    "let g:go_highlight_structs = 1
    "let g:go_highlight_interfaces = 1
    "let g:go_highlight_operators = 1
    "let g:go_highlight_build_constraints = 1
    let g:go_fmt_command = "goimports" "Use goimports instead of gofmt to insert imports
    let g:go_list_type = "quickfix"
    "\s to list interfaces implemented by the type
    au FileType go nmap <Leader>s <Plug>(go-implements)
    "\i to show type info
    au FileType go nmap <Leader>i <Plug>(go-info)

  "│-v-2 │ javascript - pangloss/vim-javascript
  "└─────┴─────────
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

  "│-v-2 │ jsx - mxw/vim-jsx
  "└─────┴─────────
    let g:jsx_ext_required = 0

  "│-v-2 │ neocomplete - Shougo/neocomplete.vim
  "└─────┴─────────
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

  "│-v-2 │ neomake - neomake/neomake
  "└─────┴─────────
    autocmd! BufWritePost * Neomake "Run on every file save
    let g:neomake_open_list = 2
    let g:neomake_list_height = 5

    let g:neomake_javascript_enabled_makers = ['eslint'] "Use eslint for syntax checking

  "│-v-2 │ nerdtree  - scrooloose/nerdtree and justr/vim-nerdtree-tabs
  "└─────┴─────────
    " Open/close NERDTree Tabs (explorer tree) with \e
    nmap <silent> <leader>e :NERDTreeTabsToggle<CR>

    " Open NERDTree at current file
    nmap <silent> <leader>E :NERDTreeFind<CR>

    " To have NERDTree always open on startup. 0 = disabled
    let g:nerdtree_tabs_open_on_console_startup = 0

    " Disable cursor line highlight in order to speed up
    " nerdtree-syntax-highlight
    let g:NERDTreeHighlightCursorline = 0

  "│-v-2 │ nerdtree-syntax-highlight  - tiagofumo/vim-nerdtree-syntax-highlight
  "└─────┴─────────
    " Disable all extensions to prevent lag
    let g:NERDTreeSyntaxDisableDefaultExtensions = 1
    let g:NERDTreeDisableExactMatchHighlight = 1
    let g:NERDTreeDisablePatternMatchHighlight = 1

    " Only change the color for extensions I commonly use
    let g:NERDTreeSyntaxEnabledExtensions = ['css', 'go', 'html', 'js', 'json', 'jsx', 'markdown', 'md', 'sh', 'vim', 'zsh']

  "│-v-2 │ signify - mhinz/signify
  "└─────┴─────────
    let g:signify_vcs_list = ['git'] " Limit support to git for speed. Why would I use anything else?
    let g:signify_mapping_next_hunk = '<leader>gj' " Go to next hunk
    let g:signify_mapping_prev_hunk = '<leader>gk' " Go to previous hunk

  "│-v-2 │ slim - slim-template/vim-slim.git
  "└─────┴─────────
    " Needed to use `doctype html` - https://github.com/slim-template/vim-slim/issues/38
    autocmd BufNewFile,BufRead *.slim setlocal filetype=slim

  "│-v-2 │ startify - mhinz/vim-startify
  "└─────┴─────────
    function! s:list_commits()
      let git = 'git'
      let commits = systemlist(git .' log --oneline | head -n5')
      let git = 'G'. git[1:]
      return map(commits, '{"line": matchstr(v:val, "\\s\\zs.*"), "cmd": "'. git .' show ". matchstr(v:val, "^\\x\\+") }')
    endfunction

    " Let us assume you have vim-devicons installed. That plugin has a function
    " `WebDevIconsGetFileTypeSymbol()` which returns an icon depending on the given
    " file. Prepend the logo to each Startify entry by putting this in your vimrc:
    function! StartifyEntryFormat()
      return 'WebDevIconsGetFileTypeSymbol(absolute_path) ." ". entry_path'
    endfunction

    " Define what get's shown on open
    let g:startify_lists = [
      \ { 'type': 'files',     'header': [   'Most Recently Used']            },
      \ { 'type': 'dir',       'header': [   'Most Recently Used - '. getcwd()] },
      \ { 'type': 'sessions',  'header': [   'Sessions']       },
      \ { 'type': 'bookmarks', 'header': [   'Bookmarks']      },
      \ { 'type': 'commands',  'header': [   'Commands']       },
      \ { 'type': function('s:list_commits'), 'header': [ 'Commits in '. getcwd()] },
      \ ]
    " When opening a file or bookmark, seek and change to the root directory
    " of the VCS (if there is one).
    let g:startify_change_to_vcs_root = 1

  "│-v-2 │ syntastic - syntastic/syntastic
  "└─────┴─────────
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

    " Point syntastic checker at locally installed `eslint` if it exists.
    if executable('node_modules/.bin/eslint')
      let b:syntastic_javascript_eslint_exec = 'node_modules/.bin/eslint'
    endif

    let g:syntastic_go_checkers = ['go', 'gofmt', 'golint', 'govet', 'errcheck']
    "let g:syntastic_mode_map = { 'mode': 'active', 'passive_filetypes': ['go'] }
    let g:syntastic_make_checkers = ['gnumake']

  "│-v-2 │ tagbar - majutsushi/tagbar
  "└─────┴─────────
    " Open tagbar with F8
    nmap <F8> :TagbarToggle<CR>
    let g:tagbar_autofocus = 1 "Automatically focus the tagbar when it is opened

  "│-v-2 │ test - janko-m/vim-test
  "└─────┴─────────
    nmap <silent> <leader>t :TestNearest<CR>
    nmap <silent> <leader>T :TestFile<CR>
    nmap <silent> <leader>a :TestSuite<CR>
    nmap <silent> <leader>l :TestLast<CR>
    nmap <silent> <leader>g :TestVisit<CR>
    " make test commands execute using dispatch.vim
    let test#strategy = "dispatch"

    " Set the NODE_ENV correctly for tests
    "let test#javascript#mocha#executable = 'NODE_ENV=test ' . test#javascript#mocha#executable()


"│-v-1 │ functions
"└─────┴─────────
  " Useful for setting the upperchase char to the same as the  lowercase char
  function! SetupCommandAlias(from, to)
    exec 'cnoreabbrev <expr> '.a:from
    \ .' ((getcmdtype() is# ":" && getcmdline() is# "'.a:from.'")'
    \ .'? ("'.a:to.'") : ("'.a:from.'"))'
  endfunction

"│-v-1 │ settings
"└─┬───┴─┬────────────────
  "│-v-2 │ appearance
  "└─┬───┴─┬────────────────
    "│-v-3 │ syntax
    "└─────┴─────────
      " enable syntax highlighting
      syntax on
    "│-v-3 │ display
    "└─────┴─────────
      " Display characters to symbolize whitespace
      "set list
      set listchars=tab:▸\ ,eol:¬
      set number " Line numbering on
      set ruler " Display location in file
      set showmatch " Show matching brackets/paranthesis
      set showcmd "Show command in the last line of the screen

      " ----- background highlight the character if line length goes over 120 -----
      highlight OverLengthIndiator ctermbg=darkyellow
      call matchadd('OverLengthIndiator', '\%121v', 100)

      " redraw only when we need to."
      set lazyredraw

    "│-v-3 │ color scheme
    "└─────┴─────────
      set background=dark " Dark background friendly
      let g:dracula_italic = 0 " Disable italics https://github.com/dracula/vim/issues/65
      color dracula "Set the color scheme
      let g:airline_theme='dracula'
      augroup dracula_customization
          au!
          autocmd ColorScheme dracula hi DraculaComment ctermfg=84
      augroup END

  "│-v-2 │ commands
  "└─┬───┴─┬────────────────
    "│-v-3 │ wildmenu
    "└─────┴─────────
      set wildmenu
      set wildmode=longest:list,full

  "│-v-2 │ editor
  "└─────┴─────────
    set tabstop=4 "Tabs take up 4 spaces
    "set shiftwidth=2
    "set softtabstop=2

  "│-v-2 │ spelling
  "└─────┴─────────
    set spelllang=en_us
  "│-v-2 │ search
  "└─────┴─────────
    set incsearch "Search as you type. Return to original location if canceled.
    set ignorecase "case insensitive searching
    set smartcase "if search isn't all lowercase, casesensitive search

  "│-v-2 │ mouse
  "└─────┴─────────
    set mouse=a "Enable the mouse use in all modes

  "│-v-2 │ files
  "└─────┴─────────
		" Triger `autoread` when files changes on disk
		" https://unix.stackexchange.com/questions/149209/refresh-changed-content-of-file-opened-in-vim/383044#383044
		" https://vi.stackexchange.com/questions/13692/prevent-focusgained-autocmd-running-in-command-line-editing-mode
		autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * if mode() != 'c' | checktime | endif
		" Notification after file change
		" https://vi.stackexchange.com/questions/13091/autocmd-event-for-autoread
		autocmd FileChangedShellPost *
			\ echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None

"│-v-1 │ mappings
"└─┬───┴─┬────────────────
  "│-v-2 │ keys
  "└─────┴─────────
    set backspace=indent,eol,start "make backspace behave like normal
    call SetupCommandAlias("Q", "q")
    call SetupCommandAlias("W", "w")

  "│-v-2 │ layout
  "└─────┴─────────
    nnoremap <silent> <leader>> :vertical resize 123<CR> "Automatically resize split to fit 120 chars

  "│-v-2 │ file shortcuts
  "└─────┴─────────
    " Quick settings access
    nnoremap <silent> <F2> :tabedit $MYVIMRC<cr>

"│-v-1 │ filetype
"└─┬───┴─┬────────────────
  "│-v-2 │ .md - markdown
  "└─────┴─────────
    autocmd BufNewFile,BufFilePre,BufRead *.md set filetype=markdown " .md == markdown. .md != modula-2

  "│-v-2 │ .ejs - embeddedjs)
  "└─────┴─────────
    autocmd BufNewFile,BufRead *.ejs set filetype=html
"│-v-1 │ footer
"└─────┴─────────
  " vim: set fmr=-v-,-^- fdm=marker cms="%s et ts=2 sw=0 sts=0 :
