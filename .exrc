let s:cpo_save=&cpo
set cpo&vim
imap <silent> <expr> <C-[> luasnip#jumpable(-1) ? '<Plug>luasnip-jump-prev' : ''
imap <silent> <expr> <C-]> luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
noremap! <silent> <Plug>luasnip-expand-repeat <Cmd>lua require'luasnip'.expand_repeat()
noremap! <silent> <Plug>luasnip-delete-check <Cmd>lua require'luasnip'.unlink_current_if_deleted()
inoremap <silent> <Plug>luasnip-jump-prev <Cmd>lua require'luasnip'.jump(-1)
inoremap <silent> <Plug>luasnip-jump-next <Cmd>lua require'luasnip'.jump(1)
inoremap <silent> <Plug>luasnip-prev-choice <Cmd>lua require'luasnip'.change_choice(-1)
inoremap <silent> <Plug>luasnip-next-choice <Cmd>lua require'luasnip'.change_choice(1)
inoremap <silent> <Plug>luasnip-expand-snippet <Cmd>lua require'luasnip'.expand()
inoremap <silent> <Plug>luasnip-expand-or-jump <Cmd>lua require'luasnip'.expand_or_jump()
inoremap <C-G>S <Plug>(nvim-surround-insert-line)
inoremap <C-G>s <Plug>(nvim-surround-insert)
cnoremap <silent> <Plug>(TelescopeFuzzyCommandSearch) e "lua require('telescope.builtin').command_history { default_text = [=[" . escape(getcmdline(), '"') . "]=] }"
inoremap <C-W> u
inoremap <C-U> u
xnoremap <silent> 	 :lua require('luasnip.util.util').store_selection()gv"_s
nnoremap  <Cmd>nohlsearch|diffupdate|normal! 
nmap <silent> <expr>  luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
smap <silent> <expr>  luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
vmap  :%s/=GetVisual()//gc<Left><Left><Left>
nmap  d
vnoremap <silent>  "+y
nmap <silent> <expr>  luasnip#jumpable(-1) ? '<Plug>luasnip-jump-prev' : ''
smap <silent> <expr>  luasnip#jumpable(-1) ? '<Plug>luasnip-jump-prev' : ''
nmap <silent> <expr>  luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
smap <silent> <expr>  luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
nnoremap  ву :lua require("dapui").toggle()
nnoremap  de :lua require("dapui").toggle()
nnoremap  З <Cmd>lua require("goto-preview").close_all_win()
nnoremap  P <Cmd>lua require("goto-preview").close_all_win()
nnoremap  зВ <Cmd>lua require("goto-preview").goto_preview_declaration()
nnoremap  pD <Cmd>lua require("goto-preview").goto_preview_declaration()
nnoremap  зш <Cmd>lua require("goto-preview").goto_preview_implementation()
nnoremap  pi <Cmd>lua require("goto-preview").goto_preview_implementation()
nnoremap  зе <Cmd>lua require("goto-preview").goto_preview_type_definition()
nnoremap  pt <Cmd>lua require("goto-preview").goto_preview_type_definition()
nnoremap  зв <Cmd>lua require("goto-preview").goto_preview_definition()
nnoremap  pd <Cmd>lua require("goto-preview").goto_preview_definition()
nnoremap  вд :lua require"dap".list_breakpoints()
nnoremap  dl :lua require"dap".list_breakpoints()
nnoremap  вс :lua require"dap".clear_breakpoints()
nnoremap  dc :lua require"dap".clear_breakpoints()
nnoremap  вИ :lua require"dap".set_breakpoint(vim.fn.input("Breakpoint condition: "))
nnoremap  dB :lua require"dap".set_breakpoint(vim.fn.input("Breakpoint condition: "))
nnoremap  ви :lua require"dap".toggle_breakpoint()
nnoremap  db :lua require"dap".toggle_breakpoint()
nnoremap  вщ :lua require"dap".step_over()
nnoremap  do :lua require"dap".step_over()
nnoremap  вш :lua require"dap".step_into()
nnoremap  di :lua require"dap".step_into()
nnoremap  вг :lua require"dap".step_out()
nnoremap  du :lua require"dap".step_out()
nnoremap  ве :lua require"dap".terminate()
nnoremap  dt :lua require"dap".terminate()
nnoremap  вв :lua require"dap".continue()
nnoremap  dd :lua require"dap".continue()
nnoremap  вз :lua require"dap.ui.widgets".preview()
nnoremap  dp :lua require"dap.ui.widgets".preview()
nnoremap  вр :lua require"dap.ui.widgets".hover()
nnoremap  dh :lua require"dap.ui.widgets".hover()
nnoremap  вк :lua require"dap".repl.open()
nnoremap  dr :lua require"dap".repl.open()
nnoremap  пь :GeminiChat 
nnoremap  gm :GeminiChat 
nnoremap <silent>  нд :let @"=fnamemodify(expand('%'), ':~:.') | echo @" .. ' was copied to the register ".'
nnoremap <silent>  yl :let @"=fnamemodify(expand('%'), ':~:.') | echo @" .. ' was copied to the register ".'
nnoremap <silent>  нз :let @"=expand('%:p') | echo @" .. ' was copied to the register ".'
nnoremap <silent>  yp :let @"=expand('%:p') | echo @" .. ' was copied to the register ".'
nnoremap <silent>  на :let @"=expand('%:t') | echo @" .. ' was copied to the register ".'
nnoremap <silent>  yf :let @"=expand('%:t') | echo @" .. ' was copied to the register ".'
nnoremap <silent>  сд :let @+=fnamemodify(expand('%'), ':~:.') | echo @+ .. ' was copied to the clipboard.'
nnoremap <silent>  cl :let @+=fnamemodify(expand('%'), ':~:.') | echo @+ .. ' was copied to the clipboard.'
nnoremap <silent>  сз :let @+=expand('%:p') | echo @+ .. ' was copied to the clipboard.'
nnoremap <silent>  cp :let @+=expand('%:p') | echo @+ .. ' was copied to the clipboard.'
nnoremap <silent>  са :let @+=expand('%:t') | echo @+ .. ' was copied to the clipboard.'
nnoremap <silent>  cf :let @+=expand('%:t') | echo @+ .. ' was copied to the clipboard.'
nnoremap  j <Cmd>lua require'telescope.builtin'.resume()
nnoremap  t <Cmd>lua require('telescope.builtin').treesitter()
nnoremap  / <Cmd>lua require'telescope.builtin'.builtin()
nnoremap  gg <Cmd>lua require("telescope").extensions.live_grep_args.live_grep_args({additional_args={"--hidden"}})
nnoremap  rr <Cmd>lua require('telescope.builtin').registers()
nnoremap  H <Cmd>lua require('telescope.builtin').highlights()
nnoremap  m <Cmd>lua require('telescope.builtin').marks({path_display={'shorten'}})
nnoremap  h <Cmd>lua require('telescope.builtin').help_tags()
nnoremap  o <Cmd>lua require('telescope.builtin').oldfiles()
nnoremap  fg <Cmd>lua require('telescope.builtin').git_status({git_icons = Git_icons})
nnoremap  e <Cmd>lua require('telescope.builtin').buffers({sort_mru=true, sort_lastused=true})
nnoremap  fz <Cmd>lua require('telescope.builtin').find_files({search_file='*.zig', results_title = 'Zig files'})
nnoremap  fl <Cmd>lua require('telescope.builtin').find_files({search_file='*.lua', results_title = 'Lua files'})
nnoremap  fp <Cmd>lua require('telescope.builtin').find_files({search_file='*.proto', results_title = 'Protobuf files'})
nnoremap  fs <Cmd>lua require('telescope.builtin').find_files({search_file='*.scala', no_ignore = true, file_ignore_patterns = {'%.semanticdb'}, results_title = 'Scala files' })
vnoremap  gg "zy<Cmd>exec 'Telescope grep_string default_text=' . escape(@z, ' ')
nnoremap  gb <Cmd>lua require('telescope.builtin').live_grep({grep_open_files=true,prompt_title = 'Live grep in buffers' })
nnoremap  ff <Cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()
nnoremap  ss <Cmd>lua require('telescope.builtin').lsp_document_symbols()
nnoremap  sf <Cmd>lua require('telescope.builtin').lsp_document_symbols({symbols={'method', 'function'}})
nnoremap  sc <Cmd>lua require('telescope.builtin').lsp_document_symbols({symbols='constant'})
nnoremap  si <Cmd>lua require('telescope.builtin').lsp_document_symbols({symbols='interface'})
nnoremap  lh <Cmd>Telescope undo
nnoremap  wd <Cmd>lua require('telescope.builtin').diagnostics({ severity_limit = 'ERROR'})
nnoremap  fC <Cmd>lua require('telescope.builtin').find_files({ find_command = { 'find', '-L', '.', '-name', '*.c', '-o', '-name', '*.h', '-o', '-name', '*.cpp' }, results_title = 'C/C++ files with symlinks' })
nnoremap  fc <Cmd>lua require('telescope.builtin').find_files({ find_command = { 'find', '.', '-name', '*.c', '-o', '-name', '*.h', '-o', '-name', '*.cpp' }, results_title = 'C/C++ files' })
nnoremap  fA <Cmd>lua require('telescope.builtin').find_files({ hidden = true })
nnoremap  fa <Cmd>lua require('telescope.builtin').find_files({file_ignore_patterns = { 'target/' }})
omap <silent> % <Plug>(MatchitOperationForward)
xmap <silent> % <Plug>(MatchitVisualForward)
nmap <silent> % <Plug>(MatchitNormalForward)
nnoremap & :&&
nnoremap '4 :Neotree show git_status
nnoremap '3 :Neotree show document_symbols
nnoremap '2 :Neotree show buffers
nnoremap '1 :Neotree show reveal
nnoremap '' :Neotree focus reveal_force_cwd
nnoremap <silent> 'cd :cd %:p:h:pwd
xnoremap <silent> < <gv
xnoremap <silent> > >gv
xnoremap <silent> <expr> @ mode() ==# 'V' ? ':normal! @'.getcharstr().'' : '@'
nnoremap <silent> QQ :bd!
xnoremap <silent> <expr> Q mode() ==# 'V' ? ':normal! @=reg_recorded()' : 'Q'
xnoremap S <Plug>(nvim-surround-visual)
nnoremap <silent> Y y$
omap <silent> [% <Plug>(MatchitOperationMultiBackward)
xmap <silent> [% <Plug>(MatchitVisualMultiBackward)
nmap <silent> [% <Plug>(MatchitNormalMultiBackward)
nnoremap <silent> [b :bprevious
nnoremap <silent> [t :tabprevious 
nnoremap <silent> [q :cprevious
omap <silent> ]% <Plug>(MatchitOperationMultiForward)
xmap <silent> ]% <Plug>(MatchitVisualMultiForward)
nmap <silent> ]% <Plug>(MatchitNormalMultiForward)
nnoremap <silent> ]b :bnext
nnoremap <silent> ]t :tabnext
nnoremap <silent> ]q :cnext
xmap a% <Plug>(MatchitVisualTextObject)
nnoremap cS <Plug>(nvim-surround-change-line)
nnoremap cs <Plug>(nvim-surround-change)
nnoremap ds <Plug>(nvim-surround-delete)
nnoremap <silent> gb 
omap <silent> g% <Plug>(MatchitOperationBackward)
xmap <silent> g% <Plug>(MatchitVisualBackward)
nmap <silent> g% <Plug>(MatchitNormalBackward)
xnoremap gS <Plug>(nvim-surround-visual-line)
xnoremap gal <Cmd>lua require('textcase').quick_replace('to_lower_case')
nnoremap gal <Cmd>lua require('textcase').quick_replace('to_lower_case')
nnoremap gaL <Cmd>lua require('textcase').lsp_rename('to_lower_case')
nnoremap gaol <Cmd>lua require('textcase').operator('to_lower_case')
xnoremap gau <Cmd>lua require('textcase').quick_replace('to_upper_case')
nnoremap gau <Cmd>lua require('textcase').quick_replace('to_upper_case')
nnoremap gaU <Cmd>lua require('textcase').lsp_rename('to_upper_case')
nnoremap gaou <Cmd>lua require('textcase').operator('to_upper_case')
xnoremap gap <Cmd>lua require('textcase').quick_replace('to_pascal_case')
nnoremap gap <Cmd>lua require('textcase').quick_replace('to_pascal_case')
nnoremap gaP <Cmd>lua require('textcase').lsp_rename('to_pascal_case')
nnoremap gaop <Cmd>lua require('textcase').operator('to_pascal_case')
xnoremap gad <Cmd>lua require('textcase').quick_replace('to_dash_case')
nnoremap gad <Cmd>lua require('textcase').quick_replace('to_dash_case')
nnoremap gaD <Cmd>lua require('textcase').lsp_rename('to_dash_case')
nnoremap gaod <Cmd>lua require('textcase').operator('to_dash_case')
xnoremap gas <Cmd>lua require('textcase').quick_replace('to_snake_case')
nnoremap gas <Cmd>lua require('textcase').quick_replace('to_snake_case')
nnoremap gaS <Cmd>lua require('textcase').lsp_rename('to_snake_case')
nnoremap gaos <Cmd>lua require('textcase').operator('to_snake_case')
xnoremap gac <Cmd>lua require('textcase').quick_replace('to_camel_case')
nnoremap gac <Cmd>lua require('textcase').quick_replace('to_camel_case')
nnoremap gaC <Cmd>lua require('textcase').lsp_rename('to_camel_case')
nnoremap gaoc <Cmd>lua require('textcase').operator('to_camel_case')
xnoremap gan <Cmd>lua require('textcase').quick_replace('to_constant_case')
nnoremap gan <Cmd>lua require('textcase').quick_replace('to_constant_case')
nnoremap gaN <Cmd>lua require('textcase').lsp_rename('to_constant_case')
nnoremap gaon <Cmd>lua require('textcase').operator('to_constant_case')
xnoremap ga. <Cmd>TextCaseOpenTelescope
nnoremap ga. <Cmd>TextCaseOpenTelescope
nnoremap <silent> j gj
nnoremap <silent> k gk
nnoremap <silent> qc :cclose
nnoremap <silent> qo :copen
nnoremap <silent> qQ :bd
nnoremap <silent> qt :tabclose
nnoremap <silent> qq :bp|bd#
nnoremap ySS <Plug>(nvim-surround-normal-cur-line)
nnoremap yS <Plug>(nvim-surround-normal-line)
nnoremap yss <Plug>(nvim-surround-normal-cur)
nnoremap ys <Plug>(nvim-surround-normal)
nnoremap zs <Cmd>lua require('telescope.builtin').spell_suggest()
nmap <silent> <expr> <C-[> luasnip#jumpable(-1) ? '<Plug>luasnip-jump-prev' : ''
smap <silent> <expr> <C-[> luasnip#jumpable(-1) ? '<Plug>luasnip-jump-prev' : ''
nmap <silent> <expr> <C-]> luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
smap <silent> <expr> <C-]> luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
snoremap <silent> <Plug>luasnip-jump-prev <Cmd>lua require'luasnip'.jump(-1)
snoremap <silent> <Plug>luasnip-jump-next <Cmd>lua require'luasnip'.jump(1)
snoremap <silent> <Plug>luasnip-prev-choice <Cmd>lua require'luasnip'.change_choice(-1)
snoremap <silent> <Plug>luasnip-next-choice <Cmd>lua require'luasnip'.change_choice(1)
snoremap <silent> <Plug>luasnip-expand-snippet <Cmd>lua require'luasnip'.expand()
snoremap <silent> <Plug>luasnip-expand-or-jump <Cmd>lua require'luasnip'.expand_or_jump()
noremap <silent> <Plug>luasnip-expand-repeat <Cmd>lua require'luasnip'.expand_repeat()
noremap <silent> <Plug>luasnip-delete-check <Cmd>lua require'luasnip'.unlink_current_if_deleted()
nnoremap <F8> :lua require"dap".step_over()
nnoremap <F7> :lua require"dap".step_into()
nnoremap <F6> :lua require"dap".step_out()
nnoremap <F33> :lua require"dap".terminate()
nnoremap <F9> :lua require"dap".continue()
vnoremap <silent> <C-Y> "+y
nnoremap <silent> <F5> :so % | echo 'script has been invoked' 
nnoremap <silent> <F4> :Lazy
nnoremap <silent> <F3> :set hlsearch!
nnoremap <silent> <F2> :set wrap!|set linebreak!
nnoremap <silent> <F1> K
xmap <silent> <Plug>(MatchitVisualTextObject) <Plug>(MatchitVisualMultiBackward)o<Plug>(MatchitVisualMultiForward)
onoremap <silent> <Plug>(MatchitOperationMultiForward) :call matchit#MultiMatch("W",  "o")
onoremap <silent> <Plug>(MatchitOperationMultiBackward) :call matchit#MultiMatch("bW", "o")
xnoremap <silent> <Plug>(MatchitVisualMultiForward) :call matchit#MultiMatch("W",  "n")m'gv``
xnoremap <silent> <Plug>(MatchitVisualMultiBackward) :call matchit#MultiMatch("bW", "n")m'gv``
nnoremap <silent> <Plug>(MatchitNormalMultiForward) :call matchit#MultiMatch("W",  "n")
nnoremap <silent> <Plug>(MatchitNormalMultiBackward) :call matchit#MultiMatch("bW", "n")
onoremap <silent> <Plug>(MatchitOperationBackward) :call matchit#Match_wrapper('',0,'o')
onoremap <silent> <Plug>(MatchitOperationForward) :call matchit#Match_wrapper('',1,'o')
xnoremap <silent> <Plug>(MatchitVisualBackward) :call matchit#Match_wrapper('',0,'v')m'gv``
xnoremap <silent> <Plug>(MatchitVisualForward) :call matchit#Match_wrapper('',1,'v'):if col("''") != col("$") | exe ":normal! m'" | endifgv``
nnoremap <silent> <Plug>(MatchitNormalBackward) :call matchit#Match_wrapper('',0,'n')
nnoremap <silent> <Plug>(MatchitNormalForward) :call matchit#Match_wrapper('',1,'n')
vnoremap <silent> <C-н> "+y
xnoremap <silent> <Plug>(openbrowser-smart-search) :call openbrowser#_keymap_smart_search('v')
nnoremap <silent> <Plug>(openbrowser-smart-search) :call openbrowser#_keymap_smart_search('n')
xnoremap <silent> <Plug>(openbrowser-search) :call openbrowser#_keymap_search('v')
nnoremap <silent> <Plug>(openbrowser-search) :call openbrowser#_keymap_search('n')
xnoremap <silent> <Plug>(openbrowser-open-incognito) :call openbrowser#_keymap_open('v', 0, ['--incognito'])
nnoremap <silent> <Plug>(openbrowser-open-incognito) :call openbrowser#_keymap_open('n', 0, ['--incognito'])
xnoremap <silent> <Plug>(openbrowser-open) :call openbrowser#_keymap_open('v')
nnoremap <silent> <Plug>(openbrowser-open) :call openbrowser#_keymap_open('n')
nnoremap <Plug>PlenaryTestFile :lua require('plenary.test_harness').test_file(vim.fn.expand("%:p"))
nnoremap <Plug>(Marks-prev-bookmark9) <Cmd> lua require'marks'.prev_bookmark9()
nnoremap <Plug>(Marks-next-bookmark9) <Cmd> lua require'marks'.next_bookmark9()
nnoremap <Plug>(Marks-toggle-bookmark9) <Cmd> lua require'marks'.toggle_bookmark9()
nnoremap <Plug>(Marks-delete-bookmark9) <Cmd> lua require'marks'.delete_bookmark9()
nnoremap <Plug>(Marks-set-bookmark9) <Cmd> lua require'marks'.set_bookmark9()
nnoremap <Plug>(Marks-prev-bookmark8) <Cmd> lua require'marks'.prev_bookmark8()
nnoremap <Plug>(Marks-next-bookmark8) <Cmd> lua require'marks'.next_bookmark8()
nnoremap <Plug>(Marks-toggle-bookmark8) <Cmd> lua require'marks'.toggle_bookmark8()
nnoremap <Plug>(Marks-delete-bookmark8) <Cmd> lua require'marks'.delete_bookmark8()
nnoremap <Plug>(Marks-set-bookmark8) <Cmd> lua require'marks'.set_bookmark8()
nnoremap <Plug>(Marks-prev-bookmark7) <Cmd> lua require'marks'.prev_bookmark7()
nnoremap <Plug>(Marks-next-bookmark7) <Cmd> lua require'marks'.next_bookmark7()
nnoremap <Plug>(Marks-toggle-bookmark7) <Cmd> lua require'marks'.toggle_bookmark7()
nnoremap <Plug>(Marks-delete-bookmark7) <Cmd> lua require'marks'.delete_bookmark7()
nnoremap <Plug>(Marks-set-bookmark7) <Cmd> lua require'marks'.set_bookmark7()
nnoremap <Plug>(Marks-prev-bookmark6) <Cmd> lua require'marks'.prev_bookmark6()
nnoremap <Plug>(Marks-next-bookmark6) <Cmd> lua require'marks'.next_bookmark6()
nnoremap <Plug>(Marks-toggle-bookmark6) <Cmd> lua require'marks'.toggle_bookmark6()
nnoremap <Plug>(Marks-delete-bookmark6) <Cmd> lua require'marks'.delete_bookmark6()
nnoremap <Plug>(Marks-set-bookmark6) <Cmd> lua require'marks'.set_bookmark6()
nnoremap <Plug>(Marks-prev-bookmark5) <Cmd> lua require'marks'.prev_bookmark5()
nnoremap <Plug>(Marks-next-bookmark5) <Cmd> lua require'marks'.next_bookmark5()
nnoremap <Plug>(Marks-toggle-bookmark5) <Cmd> lua require'marks'.toggle_bookmark5()
nnoremap <Plug>(Marks-delete-bookmark5) <Cmd> lua require'marks'.delete_bookmark5()
nnoremap <Plug>(Marks-set-bookmark5) <Cmd> lua require'marks'.set_bookmark5()
nnoremap <Plug>(Marks-prev-bookmark4) <Cmd> lua require'marks'.prev_bookmark4()
nnoremap <Plug>(Marks-next-bookmark4) <Cmd> lua require'marks'.next_bookmark4()
nnoremap <Plug>(Marks-toggle-bookmark4) <Cmd> lua require'marks'.toggle_bookmark4()
nnoremap <Plug>(Marks-delete-bookmark4) <Cmd> lua require'marks'.delete_bookmark4()
nnoremap <Plug>(Marks-set-bookmark4) <Cmd> lua require'marks'.set_bookmark4()
nnoremap <Plug>(Marks-prev-bookmark3) <Cmd> lua require'marks'.prev_bookmark3()
nnoremap <Plug>(Marks-next-bookmark3) <Cmd> lua require'marks'.next_bookmark3()
nnoremap <Plug>(Marks-toggle-bookmark3) <Cmd> lua require'marks'.toggle_bookmark3()
nnoremap <Plug>(Marks-delete-bookmark3) <Cmd> lua require'marks'.delete_bookmark3()
nnoremap <Plug>(Marks-set-bookmark3) <Cmd> lua require'marks'.set_bookmark3()
nnoremap <Plug>(Marks-prev-bookmark2) <Cmd> lua require'marks'.prev_bookmark2()
nnoremap <Plug>(Marks-next-bookmark2) <Cmd> lua require'marks'.next_bookmark2()
nnoremap <Plug>(Marks-toggle-bookmark2) <Cmd> lua require'marks'.toggle_bookmark2()
nnoremap <Plug>(Marks-delete-bookmark2) <Cmd> lua require'marks'.delete_bookmark2()
nnoremap <Plug>(Marks-set-bookmark2) <Cmd> lua require'marks'.set_bookmark2()
nnoremap <Plug>(Marks-prev-bookmark1) <Cmd> lua require'marks'.prev_bookmark1()
nnoremap <Plug>(Marks-next-bookmark1) <Cmd> lua require'marks'.next_bookmark1()
nnoremap <Plug>(Marks-toggle-bookmark1) <Cmd> lua require'marks'.toggle_bookmark1()
nnoremap <Plug>(Marks-delete-bookmark1) <Cmd> lua require'marks'.delete_bookmark1()
nnoremap <Plug>(Marks-set-bookmark1) <Cmd> lua require'marks'.set_bookmark1()
nnoremap <Plug>(Marks-prev-bookmark0) <Cmd> lua require'marks'.prev_bookmark0()
nnoremap <Plug>(Marks-next-bookmark0) <Cmd> lua require'marks'.next_bookmark0()
nnoremap <Plug>(Marks-toggle-bookmark0) <Cmd> lua require'marks'.toggle_bookmark0()
nnoremap <Plug>(Marks-delete-bookmark0) <Cmd> lua require'marks'.delete_bookmark0()
nnoremap <Plug>(Marks-set-bookmark0) <Cmd> lua require'marks'.set_bookmark0()
nnoremap <Plug>(Marks-prev-bookmark) <Cmd> lua require'marks'.prev_bookmark()
nnoremap <Plug>(Marks-next-bookmark) <Cmd> lua require'marks'.next_bookmark()
nnoremap <Plug>(Marks-delete-bookmark) <Cmd> lua require'marks'.delete_bookmark()
nnoremap <Plug>(Marks-prev) <Cmd> lua require'marks'.prev()
nnoremap <Plug>(Marks-next) <Cmd> lua require'marks'.next()
nnoremap <Plug>(Marks-preview) <Cmd> lua require'marks'.preview()
nnoremap <Plug>(Marks-deletebuf) <Cmd> lua require'marks'.delete_buf()
nnoremap <Plug>(Marks-deleteline) <Cmd> lua require'marks'.delete_line()
nnoremap <Plug>(Marks-delete) <Cmd> lua require'marks'.delete()
nnoremap <Plug>(Marks-toggle) <Cmd> lua require'marks'.toggle()
nnoremap <Plug>(Marks-setnext) <Cmd> lua require'marks'.set_next()
nnoremap <Plug>(Marks-set) <Cmd> lua require'marks'.set()
vmap <C-R> :%s/=GetVisual()//gc<Left><Left><Left>
nmap <C-W><C-D> d
nnoremap <C-L> <Cmd>nohlsearch|diffupdate|normal! 
inoremap S <Plug>(nvim-surround-insert-line)
inoremap s <Plug>(nvim-surround-insert)
inoremap <expr>  v:lua.require'nvim-autopairs'.completion_confirm()
inoremap  u
inoremap  u
imap <silent> <expr>  luasnip#jumpable(-1) ? '<Plug>luasnip-jump-prev' : ''
imap <silent> <expr>  luasnip#jumpable(1) ? '<Plug>luasnip-jump-next' : ''
xnoremap <silent> Ю >gv
xnoremap <silent> Б <gv
nnoremap <silent> л gk
nnoremap <silent> о gj
nnoremap <silent> йс :cclose
nnoremap <silent> йщ :copen
nnoremap <silent> пи 
nnoremap <silent> ЙЙ :bd!
nnoremap <silent> йЙ :bd
nnoremap <silent> йе :tabclose
nnoremap <silent> йй :bp|bd#
nnoremap <silent> Н y$
nnoremap э4 :Neotree show git_status
nnoremap э3 :Neotree show document_symbols
nnoremap э2 :Neotree show buffers
nnoremap э1 :Neotree show reveal
nnoremap ээ :Neotree focus reveal_force_cwd
nnoremap <silent> эсв :cd %:p:h:pwd
nnoremap <silent> ъй :cnext
nnoremap <silent> ъе :tabnext
nnoremap <silent> ъи :bnext
nnoremap <silent> хй :cprevious
nnoremap <silent> хе :tabprevious 
nnoremap <silent> хи :bprevious
cabbr me compiler zig_build|silent make -Doptimize=ReleaseFast emulate|bel copen
cabbr mkt compiler zig_build|silent make test|bel copen
cabbr mk cclose|compiler zig_build|silent make|bel copen
cabbr mks compiler zig_test|silent make|bel copen
let &cpo=s:cpo_save
unlet s:cpo_save
set completeopt=menuone,noinsert
set foldlevelstart=99
set formatoptions=cjrlq
set grepformat=%f:%l:%c:%m
set grepprg=rg\ --vimgrep\ --no-heading\ --smart-case
set ignorecase
set langmap=ФИСВУАПРШОЛДЬТЩЗЙКЫЕГМЦЧНЯЖ;ABCDEFGHIJKLMNOPQRSTUVWXYZ:,фисвуап��шолдьтщзйкыегмцчня;abcdefghijklmnopqrstuvwxyz
set laststatus=3
set noloadplugins
set packpath=/opt/homebrew/Cellar/neovim/0.12.3/share/nvim/runtime
set runtimepath=~/.config/nvim,~/.local/share/nvim/site,~/.local/share/nvim/lazy/lazy.nvim,~/.local/share/nvim/lazy/nui.nvim,~/.local/share/nvim/lazy/neo-tree.nvim,~/.local/share/nvim/lazy/nvim-nio,~/.local/share/nvim/lazy/nvim-dap-ui,~/.local/share/nvim/lazy/tree-sitter-manager.nvim,~/.local/share/nvim/lazy/goto-preview,~/.local/share/nvim/lazy/nvim-autopairs,~/.local/share/nvim/lazy/cmp_luasnip,~/.local/share/nvim/lazy/cmp-nvim-lsp-signature-help,~/.local/share/nvim/lazy/cmp-path,~/.local/share/nvim/lazy/cmp-buffer,~/.local/share/nvim/lazy/nvim-cmp,~/.local/share/nvim/lazy/LuaSnip,~/.local/share/nvim/lazy/nvim-dap-go,~/.local/share/nvim/lazy/nvim-dap,~/.local/share/nvim/lazy/gitsigns.nvim,~/.local/share/nvim/lazy/nvim-treesitter-textobjects,~/.local/share/nvim/lazy/edge,~/.local/share/nvim/lazy/one-nvim,~/Projects/nvim/gemini.nvim,~/.local/share/nvim/lazy/\ nightfox,~/.local/share/nvim/lazy/lualine-lsp-progress,~/Projects/nvim/lualine-ex,~/.local/share/nvim/lazy/nvim-web-devicons,~/.local/share/nvim/lazy/lualine.nvim,~/.local/share/nvim/lazy/onedarkpro.nvim,~/.local/share/nvim/lazy/indent-blankline.nvim,~/.config/nvim/lua/plugins,~/.local/share/nvim/lazy/cmp-nvim-lsp,~/.local/share/nvim/lazy/langmapper.nvim,~/.local/share/nvim/lazy/open-browser.vim,~/.local/share/nvim/lazy/plantuml-syntax,~/.local/share/nvim/lazy/plantuml-previewer.vim,~/.local/share/nvim/lazy/vim-koka,~/.local/share/nvim/lazy/lspsaga.nvim,~/.local/share/nvim/lazy/plenary.nvim,~/.local/share/nvim/lazy/marks.nvim,~/.local/share/nvim/lazy/vim-replace,~/.local/share/nvim/lazy/nvim-surround,~/.local/share/nvim/lazy/which-key.nvim,~/.local/share/nvim/lazy/telescope-live-grep-args.nvim,~/.local/share/nvim/lazy/telescope-zf-native.nvim,~/.local/share/nvim/lazy/telescope.nvim,~/.local/share/nvim/lazy/text-case.nvim,~/.local/share/nvim/lazy/auto-save.nvim,~/.local/share/nvim/lazy/catppuccin,/opt/homebrew/Cellar/neovim/0.12.3/share/nvim/runtime,/opt/homebrew/Cellar/neovim/0.12.3/share/nvim/runtime/pack/dist/opt/matchit,/opt/homebrew/Cellar/neovim/0.12.3/lib/nvim,~/.local/state/nvim/lazy/readme,~/.local/share/nvim/lazy/cmp_luasnip/after,~/.local/share/nvim/lazy/cmp-nvim-lsp-signature-help/after,~/.local/share/nvim/lazy/cmp-path/after,~/.local/share/nvim/lazy/cmp-buffer/after,~/.local/share/nvim/lazy/onedarkpro.nvim/after,~/.local/share/nvim/lazy/indent-blankline.nvim/after,~/.local/share/nvim/lazy/cmp-nvim-lsp/after,~/.local/share/nvim/lazy/catppuccin/after
set shellpipe=2>&1|grep\ ':\ error:'|sort|uniq|tee
set shortmess=tcCoOlT
set smartcase
set spelllang=ru,en
set spellsuggest=best,5
set statusline=%#lualine_transparent#
set termguicolors
set textwidth=100
set undodir=~/.vim/undodir
set undofile
set updatetime=300
set window=45
" vim: set ft=vim :
