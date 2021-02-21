" initialize default wiki
call zettel#vimwiki#initialize_wiki_number()
" get active VimWiki directory
let g:zettel_dir = vimwiki#vars#get_wikilocal('path') "VimwikiGet('path',g:vimwiki_current_idx)

" FZF command used in the ZettelSearch command
if !exists('g:zettel_fzf_command')
  let g:zettel_fzf_command = "ag"
endif

if !exists('g:zettel_fzf_options')
  let g:zettel_fzf_options = ['--exact', '--tiebreak=end']
endif

" vimwiki files can have titles in the form of %title title content
function! s:get_zettel_title(filename)
  return zettel#vimwiki#get_title(a:filename)
endfunction

" fzf returns selected filename and matched line from the file, we need to
" strip the unnecessary text to get just the filename
function! s:get_fzf_filename(line)
  " line is in the following format:
  " filename:linenumber:number:matched_text
  " remove spurious text from the line to get just the filename
  let filename = substitute(a:line, ":[0-9]\*:[0-9]\*:.\*$", "", "")
  return filename
endfunction

function! s:get_fzf_line_number(line)
  " line is in the following format:
  " filename:linenumber:columnnumber:matched_text
  " remove spurious text from the line to get just the filename
  let line_number = split(a:line, ":")[1]
  return line_number
endfunction

" get clean wiki name from a filename
function! s:get_wiki_file(filename)
   let fileparts = split(a:filename, '\V.')
   return join(fileparts[0:-2],".")
endfunction

function! s:paste_link(link, cursor_pos)
  let line = getline('.')
  " replace the [[ with selected link and title
  let caret = col('.')
  call setline('.', strpart(line, 0, caret) . a:link .  strpart(line, caret))
  call cursor(line('.'), caret + len(a:link) - a:cursor_pos)
  call feedkeys("a", "n")
endfunction


" execute fzf function
function! zettel#fzf#execute_fzf(a, b, options)
  " search only files in the current wiki syntax

  let l:fullscreen = 0

  if g:zettel_fzf_command == "ag"
    let search_ext = "--" . substitute(vimwiki#vars#get_wikilocal('ext'), '\.', '', '')
    let query =  empty(a:a) ? '^(?=.)' : a:a
    let options_ag =  empty(a:b) ? '' : a:b
    let l:fzf_command = g:zettel_fzf_command . ' ' . search_ext . ' ' . options_ag . ' --color --smart-case --nogroup --column ' . shellescape(query)   " --ignore-case --smart-case
  else
    " use grep method for other commands
    let search_ext = "*" . vimwiki#vars#get_wikilocal('ext')
    let l:fzf_command = g:zettel_fzf_command . " " . shellescape(a:a) . ' ' . search_ext
  endif

  return fzf#vim#grep(l:fzf_command, 1, fzf#vim#with_preview(a:options), l:fullscreen)
endfunction


" insert link for the searched zettel in the current note
function! zettel#fzf#wiki_search(line,...)
  let filename = s:get_fzf_filename(a:line)
  let title = s:get_zettel_title(filename)
  " insert the filename and title into the current buffer
  let wikiname = s:get_wiki_file(filename)
  " if the title is empty, the link will be hidden by vimwiki, use the filename
  " instead
  if empty(title)
    let title = wikiname
  end
  let link = zettel#vimwiki#format_search_link(wikiname, title)
  call <SID>paste_link(link, 2)
endfunction

" search for a note and the open it in Vimwiki
function! zettel#fzf#search_open(line,...)
  let l:line_number = s:get_fzf_line_number(a:line)
  let filename = s:get_fzf_filename(a:line)
  let wikiname = s:get_wiki_file(filename)
  if !empty(wikiname)
    " open the selected note using this Vimwiki function
    " it will keep the history of opened pages, so you can go to the previous
    " page using backspace
    echom("[DEBUG] filename: " . filename)
    echom("[DEBUG] wikiname: " . wikiname)
    echom("[DEBUG] dir: " . g:zettel_dir)
    echom("[DEBUG] wikidir: " . vimwiki#vars#get_wikilocal('path'))
    call vimwiki#base#open_link(':e +' . l:line_number . ' ' , wikiname)
  endif
endfunction

" get options for fzf#vim#with_preview function
" pass empty dictionary {} if you don't want additinal_options
function! zettel#fzf#preview_options(sink_function, additional_options)
  let options = {'sink':function(a:sink_function),
      \'down': '~40%',
      \'dir':g:zettel_dir,
      \'options':g:zettel_fzf_options}
  " make it possible to pass additional options that overwrite the default
  " ones
  let options = extend(options, a:additional_options)
  return options
endfunction

" helper function to open FZF preview window and pass one selected file to a
" sink function. useful for opening found files
function! zettel#fzf#sink_onefile(params, sink_function,...)
  " get optional argument that should contain additional options for the fzf
  " preview window
  let additional_options = get(a:, 1, {})
  call zettel#fzf#execute_fzf(a:params,
      \'--skip-vcs-ignores', fzf#vim#with_preview(zettel#fzf#preview_options(a:sink_function, additional_options)))
endfunction


" open wiki page using FZF search
function! zettel#fzf#execute_open(params)
  call zettel#fzf#sink_onefile(a:params, 'zettel#fzf#search_open')
endfunction

" return list of unique wiki pages selected in FZF
function! zettel#fzf#get_files(lines)
  " remove duplicate lines
  let new_list = []
  for line in a:lines
    if line !=""
      let new_list = add(new_list, s:get_fzf_filename(line))
    endif
  endfor
  return uniq(new_list)
endfunction

" map between Vim filetypes and Pandoc output formats
let s:supported_formats = {
      \"tex":"latex",
      \"latex":"latex",
      \"markdown":"markdown",
      \"wiki":"vimwiki",
      \"md":"markdown",
      \"org":"org",
      \"html":"html",
      \"default":"markdown",
\}

" this global variable can hold additional mappings between Vim and Pandoc
if exists('g:export_formats')
  let s:supported_formats = extend(s:supported_formats, g:export_formats)
endif

" return section title depending on the syntax
function! s:make_section(title, ft)
  if a:ft ==? "md"
    return "# " . a:title
  else
    return "= " . a:title . " ="
  endif
endfunction

" this function is just a test for retrieving multiple results from FZF. see
" plugin/zettel.vim for call example
function! zettel#fzf#insert_note(lines)
  " get Pandoc output format for the current file filetype
  let output_format = get(s:supported_formats,&filetype, "markdown")
  let lines_to_convert = []
  let input_format = "vimwiki"
  for line in zettel#fzf#get_files(a:lines)
    " convert all files to the destination format
    let filename = vimwiki#vars#get_wikilocal('path',0). line
    let ext = fnamemodify(filename, ":e")
    " update the input format
    let input_format = get(s:supported_formats, ext, "vimwiki")
    " convert note title to section
    let sect_title = s:make_section( zettel#vimwiki#get_title(filename), ext)
    " find start of the content
    let header_end = zettel#vimwiki#find_header_end(filename)
    let lines_to_convert = add(lines_to_convert, sect_title)
    let i = 0
    " read note contents without metadata header
    for fline in readfile(filename)
      if i >= header_end
        let lines_to_convert = add(lines_to_convert, fline)
      endif
      let i = i + 1
    endfor
  endfor
  let command_to_execute = "pandoc -f " . input_format . " -t " . output_format
  echom("Executing :" .command_to_execute)
  let result = systemlist(command_to_execute, lines_to_convert)
  call append(line("."), result)
  call setqflist(map(zettel#fzf#get_files(a:lines), '{ "filename": v:val }'))
endfunction


" ------------------------------------------------------------------------
" TODO kraxli:
function! zettel#fzf#anchor_query(search_string)

  " specific default search-patters for tags and headers & titles
  let l:pattern_base = ''  " '\.' or  '\\H\{2,\}'
  " let l:tag_pattern_base_tag = '\[^\\h\\n\\r\]\{2,\}'   " '\[^\D\W\\n\\r\:\]\{2,\}'
  let l:tag_pattern_base_tag = l:pattern_base
  let l:newline = '\(\?\|\^\|\\h\+\)'
  let l:newline_or_space = '\\h\\n\\r\\Z'
  let l:pat_special_chars = '\[\]\\/\(\)'
  let l:pat_http = '\(http\)\(s\?\)'

  let l:string2search = empty(a:search_string) ?  l:pattern_base : get(a:, 'search_string',  l:pattern_base)
  let l:string2search4tag = empty(a:search_string) ?  l:tag_pattern_base_tag : get(a:, 'search_string',  l:tag_pattern_base_tag)
  let l:fullscreen = get(a:, 'bang', 0) " get(a:, 2, 0)

  let l:query_vimwiki_tag = '\(\?\|\[^'. l:pat_http . '\]\|\[^\\H\\n\\r\]\):\\K\[^' . l:newline_or_space . '\]\*'. l:string2search4tag .  '\[^' . l:newline_or_space . '\]\*\(\?\=:\)'  " (\?\=:\[' . l:newline_or_space . '\]\)'
  let l:query_mkd_tag = '\[^\\H\\n\\r\]\+\#\\K\[^' . l:newline_or_space . l:pat_special_chars . '\#\]\*'. l:string2search4tag .  '\[^' . l:newline_or_space . '\]\*\(\?\=\[' . l:newline_or_space . '\]\)'

  let l:query_mkd_header = '\[\\n\\r\]\[\\h\]\*' . '\#\+\\h\+\\K\[^\\n\\r\]\*' . l:string2search
  " '\.\*'  " \(\?\<\=#\)
  let l:query_mkd_title = l:newline . '^title:\\h\+\\K\[^'. l:newline_or_space . '\]\*' . l:string2search . '\.\*'

  " TODO kraxli: anker for bold text
  " let l:query_bold = l:newline_or_space . '**\[^\\h\\n\\r\]\*'. l:string2search . '\\H\*\(\?\=**\)'
  " let l:query_bold = '**\\K\[^\\h\\n\\r\]\*'. l:string2search  .'\\H\*\(\?\=**\)'

  let l:query = l:query_vimwiki_tag . '\|' . l:query_mkd_title  . '\|'. l:query_mkd_header . '\|' . l:query_mkd_tag
  return l:query
endfunction

" helper function to create silversearcher (ag) command for anchors
function! zettel#fzf#command_anchor(query)

  if !executable('ag') || vimwiki#vars#get_wikilocal('syntax') != 'markdown'
    echomsg('function zettel#fzf#anchor_reference() works on markdown files only and requires silver-searcher (ag)')
    return
  endif

  let l:options_ag = '--md --color --ignore-case  --column ' " --ignore-case --smart-case --no-group

  let l:query = zettel#fzf#anchor_query(a:query)
  return 'ag ' . l:options_ag . l:query
endfunction

" helper function to open FZF preview window with anchors
function! zettel#fzf#anchor_reference(query, sink_function, bang)

  " let additional_options = get(a:, 1, {})
  let additional_options = {}

  let l:fullscreen = get(a:, 'bang', 0) " get(a:, 2, 0)
  let l:specs = {'sink':  function('zettel#fzf#search_open'), 'options': ['--layout=reverse', '--info=inline'], 'window': { 'width': 0.9, 'height': 0.6 }}
  " , "--preview='bat --color=always --style=header,grid --line-range :300
  let l:cmd = zettel#fzf#command_anchor(a:query)

  " return fzf#vim#grep('ag ' . l:options_ag . l:query, 1, fzf#vim#with_preview(l:specs), l:fullscreen)
  return fzf#vim#grep(l:cmd, 1, fzf#vim#with_preview(zettel#fzf#preview_options(a:sink_function, additional_options)), l:fullscreen)

endfunction

function! s:create_anchor(line, file_name)
  let l:line_red = substitute(a:line, a:file_name . ':\d\+:\d\+:', '', '')
  let g:line_red = l:line_red  " TODO why do I use this??

  " headers
  let pattern2disp = substitute(l:line_red, '\s*#\+\s\+', '#', '')
  if pattern2disp != l:line_red | return pattern2disp | endif
  " title
  let pattern2disp = substitute(l:line_red, '^title:.*', '', '')
  if pattern2disp != l:line_red | return pattern2disp | endif
  " tags
  let pattern2disp = <SID>tag_reducer(l:line_red)
  if pattern2disp != l:line_red | return pattern2disp | endif

  " TODO add bold anchors

  " TODO add filename to rest of anchor

  return ''
endfunction

function! zettel#fzf#anchor_reducer(line)
  let file_name = s:get_fzf_filename(a:line)
  let anchor = <sid>create_anchor(a:line, file_name)
  return file_name . anchor
endfunction


" insert link for the searched zettel in the current note
function! zettel#fzf#anchor_insert(line,...)
  let line_nr = split(a:line, ':')[1]
  let file_name = s:get_fzf_filename(a:line)
  let anchor = <sid>create_anchor(a:line, file_name)
  let file_ext = vimwiki#vars#get_wikilocal('ext')  " remove

  " -- reduced form of links
  " let link = zettel#fzf#anchor_reducer(a:line)
  " -- full links
  let link =  <sid>create_link(anchor, line_nr, file_name)
  let title = substitute(file_name, file_ext, '', '')  . anchor
  let link_titled = zettel#vimwiki#format_file_title("[%title](%link)", link, title)
  call <SID>paste_link(link_titled, 0)
endfunction


" TODO kraxli:
" create full links e.g. filename#header1#header2#tag
function! s:create_link(anchor, line_nr, filename) abort

  let rx_h = vimwiki#vars#get_syntaxlocal('rxH')
  let rx_header = vimwiki#vars#get_syntaxlocal('header_search')
  let rx_code = vimwiki#vars#get_syntaxlocal('char_code')

  " let PROXIMITY_LINES_NR = 2
  " let header_line_nr = - (2 * PROXIMITY_LINES_NR)
  let is_code_block = 0

  let link = a:anchor
  let line_nr = a:line_nr - 1
  let file = readfile(a:filename)[0:line_nr]
  let header_level_prev =  <sid>get_header_level(file[line_nr], rx_h)

  while line_nr > 1
    let line_nr -= 1
    let line = file[line_nr]

    " ignore code blocks
    let is_code_boarder = match(line, rx_code . '\{3,}', '') >= 0
    if is_code_boarder | let is_code_block = !is_code_block | endif
    if is_code_block | continue | endif

    " process headers
    if match(line, rx_header, 'g') < 0 | continue | endif
    let header_level = <sid>get_header_level(line, rx_h)
    if header_level == header_level_prev | continue | endif
    let link = substitute(trim(line), rx_h . '\+\s\+', '#', '') . link  " '\s*#\+\s\+'
    if header_level == 1 | break | endif
    let header_level_prev = copy(header_level)
  endwhile

  return a:filename . link
endfunction

function s:get_header_level(line, rx_h)
  let header_symbols = matchstr(a:line, '^\s*\(' . a:rx_h . '\{1,6}\)\s\+')
  let header_level = count(header_symbols, a:rx_h)
  return header_level
endfunction

" TODO kraxli: lua version
" see https://awesomeopensource.com/project/nanotee/nvim-lua-guide
" :lua print('small lua snippet')

" lua << EOF
" local mod = require('mymodule')
" local tbl = {1, 2, 3}
"
" for k, v in ipairs(tbl) do
"     mod.method(v)
" end
"
" print(tbl)
" EOF


function! s:tag_reducer(pattern)
    let pattern2disp = a:pattern

    " vimwiki tags
    let pattern2disp = substitute(pattern2disp, '.*:\(\S\+\):.*', '#\1', '')

    " other tags
    " let pattern2disp = substitute(pattern2disp, '.*#\(\S\+\).*', '#\1', '')
    " let pattern2disp = substitute(pattern2disp, '.*&&\(\S\+\).*', '#\1', '')
    " let pattern2disp = substitute(pattern2disp, '.*!\(\S\+\).*', '#\1', '')

    return pattern2disp
endfunction


" so far unused
function! zettel#fzf#anchor_complete()
  let pattern = ''
  return fzf#vim#complete(fzf#wrap({'source': zettel#fzf#command_anchor(pattern), 'reducer': { lines ->  zettel#fzf#anchor_reducer(lines[0])}}))
endfunction


"vim: set foldmethod=indent
