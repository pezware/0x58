" basics {{{
set backspace=indent,eol,start
set encoding=utf-8
set scrolloff=3
set autoindent
set showmode
set showcmd
set ttyfast
set laststatus=1
set hlsearch
set incsearch
set hidden
set showtabline=0
set fo+=r
set clipboard=unnamed
set nocompatible
set mouse=
hi ColorColumn ctermbg=lightgrey guibg=lightgrey
autocmd InsertLeave,WinEnter * set cursorline
autocmd InsertEnter,WinLeave * set nocursorline
autocmd BufWritePre * :%s/\s\+$//e
" }}}

" keys {{{
let mapleader = ","
inoremap jj <esc>
nnoremap <leader><space> :noh<cr>
nnoremap <S-Tab> :bn<cr>
" basic bufffer command: :E :ls :bn :bp :vp C-w C-w c
nnoremap <up> <nop>
nnoremap <down> <nop>
nnoremap <left> <nop>
nnoremap <right> <nop>
nnoremap <C-N> <down>
nnoremap <C-P> <up>
nnoremap ; :
nnoremap j gj
nnoremap k gk
nnoremap <leader>ev :vsplit ~/.vimrc<cr>
nnoremap <leader>sv :source ~/.vimrc<cr>
cnoremap w!! w !sudo tee > /dev/null %

set foldmethod=marker
set foldmarker={{{,}}}
" }}}

" theme {{{
" let g:solarized_termcolors=256
let g:solarized_bold=1
let g:solarized_termtrans = 1
syntax enable
set background=dark
filetype on
colorscheme solarized
" }}}

" Random Settings for whatever {{{
iabbrev <buffer> #.. # ----------

fun! SetMyTodos()
  syn match myTodos /\%\(TOFIX\)\|\%\(NOTE\)\|\%\(REM\)\|\%\(TODO\)\|\%\(HW\)\|\%\(DRAFT\)\|\%\(START\)\|\%\(END\)/
  hi myTodos ctermbg='lightyellow' ctermfg='red' cterm='bold'
endfu
autocmd bufenter * :call SetMyTodos()
autocmd filetype * :call SetMyTodos()

function! TabMessage(cmd)
  redir => message
  silent execute a:cmd
  redir END
  if empty(message)
    echoerr "no output"
  else
    leftabove new
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodified
    silent put=message
  endif
endfunction

command! -nargs=+ -complete=command TabMessage call TabMessage(<q-args>)

" }}}

" sessions {{{
function! MakeSession()
  let b:sessiondir = $HOME . "/.vim/sessions"
  if (filewritable(b:sessiondir) != 2)
    exe 'silent !mkdir -p ' b:sessiondir
    redraw!
  endif
  let b:filename = b:sessiondir . '/session.vim'
  exe "mksession! " . b:filename
endfunction

function! LoadSession()
  let b:sessiondir = $HOME . "/.vim/sessions"
  let b:sessionfile = b:sessiondir . "/session.vim"
  if (filereadable(b:sessionfile))
    exe 'source ' b:sessionfile
  else
    echo "New session"
  endif
endfunction

" Adding automatons for when entering or leaving vim
if (argc() ==0)
  au VimEnter * nested :call LoadSession()
  au VimLeave * :call MakeSession()
endif

" }}}

" vim-plug and gopls {{{
" call plug#begin('~/.vim/plugged')
call plug#begin(has('nvim') ? stdpath('data') . '/plugged' : '~/.vim/plugged')

Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
Plug 'maralla/completor.vim'
" Plug 'kyouryuukunn/completor-necovim'
Plug 'junegunn/fzf' , { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'https://github.com/github/copilot.vim'

call plug#end()

let g:completor_filetype_map = {}
let g:completor_filetype_map.go = {'ft': 'lsp', 'cmd': 'gopls -remote=auto'}"
" vim-go
let g:go_def_mode='gopls'
let g:go_info_mode='gopls'
"let g:go_fmt_command = "goimports"
"let g:go_autodetect_gopath = 1
"let g:go_list_type = "quickfix"

"let g:go_highlight_types = 1
"let g:go_highlight_fields = 1
"let g:go_highlight_functions = 1
"let g:go_highlight_function_calls = 1
"let g:go_highlight_extra_types = 1
"let g:go_highlight_generate_tags = 1

let g:completor_python_binary = '~/adminvenv/bin/python'
let g:python3_host_prog = '~/adminvenv/bin/python'

" }}}

" disable swap for files larger than 10M {{{

augroup LargeFile
        let g:large_file = 10485760 " 10MB

        " Set options:
        "   eventignore+=FileType (no syntax highlighting etc
        "   assumes FileType always on)
        "   noswapfile (save copy of file)
        "   bufhidden=unload (save memory when other file is viewed)
        "   buftype=nowritefile (is read-only)
        "   undolevels=-1 (no undo possible)
        au BufReadPre *
                \ let f=expand("<afile>") |
                \ if getfsize(f) > g:large_file |
                        \ set eventignore+=FileType |
                        \ setlocal noswapfile bufhidden=unload buftype=nowrite undolevels=-1 |
                \ else |
                        \ set eventignore-=FileType |
                \ endif
augroup END

" }}}


" format {{{
" retab set et, gg=G:retab!
set ts=2 sw=2 et fdm=marker foldlevel=0
set expandtab
" }}}


" githut copilot {{{

let g:copilot_filetypes = {
    \ 'javascript': v:true,
    \ 'typescript': v:true,
    \ 'go': v:true,
    \ 'python': v:true,
    \ 'gitcommit': v:true,
    \ 'markdown': v:true,
    \ 'yaml': v:true,
    \ 'vim': v:true,
    \ 'terraform': v:true,
    \ 'typescriptreact': v:true,
    \ 'text': v:true,
    \ }
" }}}
let g:copilot_workspace_folders = [ expand('~/src') ]


if has('nvim')
" Neovim only features
else
" Vim only features
endif
