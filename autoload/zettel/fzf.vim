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
  let line = getline('.')
  " replace the [[ with selected link and title
  let caret = col('.')
  call setline('.', strpart(line, 0, caret - 2) . link .  strpart(line, caret))
  call cursor(line('.'), caret + len(link) - 2)
  call feedkeys("a", "n")
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
  " Todo: move this to execute_open
  call setqflist(map(zettel#fzf#get_files(a:lines), '{ "filename": v:val }'))
endfunction


" ------------------------------------------------------------------------
" TODO kraxli:
function! zettel#fzf#anchor_query(search_string)

  " let l:tag_pattern_base = '\[A-Za-z0-9-_#~@%\]\{2,\}'  " '\\H\{2,\}'
  " TODO kraxli: default / base patterns need to be tag, header, title
  " specific
  let l:tag_pattern_base = '\.'  " '\\H\{2,\}'
  let l:tag_pattern_base_tag = '\[^\\h\\n\\r\]'
  let l:newline = '\(\?\|\^\|\\h\+\)'
  let l:newline_or_space = '\[\\h\\n\\r\]\+'

  let l:string2search = empty(a:search_string) ?  l:tag_pattern_base : get(a:, 'search_string',  l:tag_pattern_base)
  let l:string2search4tag = empty(a:search_string) ?  l:tag_pattern_base_tag : get(a:, 'search_string',  l:tag_pattern_base_tag)
  let l:fullscreen = get(a:, 'bang', 0) " get(a:, 2, 0)

  " TODO kraxli: don't highlight (include in match) # charachter when it is at the beginning of a line
  " TODO kraxli: markdown tags
  " let l:query_mkd_tag = l:newline_or_space . '\#\[^\#\]\+\\K\[^\\h\\n\\r\]\*' . l:string2search . '\\H\*'  " \(\?\<\=#\)

  let l:pat_http = '\(http\)\(s\?\)'
  " TODO kraxli:
  " - possibly just parse the .vimwiki_tags file: ag --hidden  -G \(.vimwiki_tags$\) test
  " - multi-match flag/mode: /g
  let l:query_vimwiki_tag = '\(\?\|\[^'. l:pat_http . '\]\|\[^\\H\\n\\r\]\):\\K\[^\\n\\h\\r\]\*'. l:string2search4tag .  '\[^\\h\\n\\r\\Z\]\*\(\?\=:\[\\h\\n\\r\]\)' " -> (best?)
  " let l:query_vimwiki_tag = '\(\?\|\[^'. l:pat_http . '\]\|\[^\\H\\n\\r\]\):\\K\(\?\|\[^\\h\\n\\r\]\+\|\\H\*\)'. l:string2search .  '\[^\\h\\n\\r\\Z\]\*\(\?\=:\)' " -> ok
  " '\\H\*\(\?\=:\)'  "\(\?\<\=:\)\\K

  let l:query_mkd_header = l:newline_or_space . '\#\\h\+\\K\[^\\n\\r\]\*' . l:string2search  " . '\[^\\n\\r\]\*'
  " '\.\*'  " \(\?\<\=#\)
  let l:query_mkd_title = l:newline . '^title:\\h\+\\K\[^\\n\\h\\r\]\*' . l:string2search . '\.\*' " '\\X'

  " TODO kraxli: anker for bold text
  " let l:query_bold = l:newline_or_space . '**\[^\\h\\n\\r\]\*'. l:string2search . '\\H\*\(\?\=**\)'
  " let l:query_bold = '**\\K\[^\\h\\n\\r\]\*'. l:string2search  .'\\H\*\(\?\=**\)'

  let l:query = l:query_vimwiki_tag . '\|' . l:query_mkd_title  . '\|'. l:query_mkd_header
  " let l:query = l:query_vimwiki_tag . '\|\(' . l:query_mkd_tag . '\)\|\(' . l:query_mkd_title  . '\)\|\('. l:query_mkd_header . '\)'
  return l:query
endfunction


" helper function to open FZF preview window and ....
function! zettel#fzf#anchor_reference(query, sink_function, bang)

  " call zettel#fzf#anchor_reference('vim', 'zettel#fzf#search_open', <bang>0)

  if !executable('ag') || vimwiki#vars#get_wikilocal('syntax') != 'markdown'
    echomsg('function zettel#fzf#anchor_reference() works on markdown files only and requires silver-searcher (ag)')
    return
  endif

  " let additional_options = get(a:, 1, {})
  let additional_options = {}

  let l:query = zettel#fzf#anchor_query(a:query)
  " echomsg(l:query)

  let l:fullscreen = get(a:, 'bang', 0) " get(a:, 2, 0)
  let l:options_ag = '--md --color --ignore-case ' " --ignore-case --smart-case --no-group
  " https://sourcegraph.com/github.com/junegunn/fzf/-/blob/README-VIM.md
  let l:specs = {'sink':  function('zettel#fzf#search_open'), 'options': ['--layout=reverse', '--info=inline'], 'window': { 'width': 0.9, 'height': 0.6 }}
  " , "--preview='bat --color=always --style=header,grid --line-range :300
  " {}'""

  " return fzf#vim#grep('ag ' . l:options_ag . l:query, 1, fzf#vim#with_preview(l:specs), l:fullscreen)
  " return fzf#vim#grep('ag ' . l:options_ag . l:query, 1, fzf#vim#with_preview(), l:fullscreen)
  return fzf#vim#grep('ag ' . l:options_ag . l:query, 1, fzf#vim#with_preview(zettel#fzf#preview_options(a:sink_function, additional_options)), l:fullscreen)

  " return zettel#fzf#execute_fzf(l:query,
  "  \'--skip-vcs-ignores', fzf#vim#with_preview(zettel#fzf#preview_options(a:sink_function, additional_options)))
endfunction


function! zettel#fzf#anchor_reducer(line)
    let pattern2disp = a:line
    let file_ext = vimwiki#vars#get_wikilocal('ext')
    " CHECK: needs to include the dot: e.g. '.md'

    " TODO: search for headers, tags, titles and replace accordingly
    let pattern2disp = substitute(substitute(pattern2disp, file_ext . ':\d\+:', '', ''), ' ', '', '')

    " headers
    let pattern2disp = substitute(pattern2disp, '#\+', '#', '')
    " title
    let pattern2disp = substitute(pattern2disp, 'title:.*', '', '')
    " tags
    let pattern2disp = <SID>tag_reducer(pattern2disp)
    " bold
    " TODO

    return pattern2disp
endfunction


function! s:tag_reducer(line)
    let pattern2disp = a:line

    " vimwiki tags
    let pattern2disp = substitute(pattern2disp, '.*:\(\S\+\):.*', '#\1', '')

    " other tags
    let pattern2disp = substitute(pattern2disp, '.*#\(\S\+\).*', '#\1', '')
    " let pattern2disp = substitute(pattern2disp, '.*&&\(\S\+\).*', '#\1', '')
    " let pattern2disp = substitute(pattern2disp, '.*!\(\S\+\).*', '#\1', '')

    return pattern2disp
endfunction


" inoremap <expr> <c-r> fzf#vim#complete(fzf#wrap({'source': ['a', 'b']})) " -> works

" function('zettel#fzf#anchor_reference' , 'query, sink_function, bang')

" function! s:reduce_line(lines)
"   return join(split(a:lines[0], '\t\zs')[3:], '')
" endfunction
" 
" 
" function! fzf#vim#complete#line(...)
"   let [display_bufnames, lines] = fzf#vim#_lines(0)
"   let nth = display_bufnames ? 4 : 3
"   return fzf#vim#complete(s:extend({
"  \ 'prefix':  '^.*$',
"  \ 'source':  lines,
"  \ 'options': '--tiebreak=index --ansi --nth '.nth.'.. --tabstop=1',
"  \ 'reducer': s:function('s:reduce_line')}, get(a:000, 0, fzf#wrap())))
" endfunction
" 
" 

" <plug>(fzf-complete-line)
" imap <c-x><c-l> <plug>(fzf-complete-line)

"  TODO: how to treat <expr> as input??
" au FileType markdown,vimwiki inoremap <expr> <c-r> fzf#vim#complete(fzf#wrap({'source': "ag '\(\(\(^\h*#+\)\\h+\[^#\]\)\|\(title:.*\)\|\(.*:\\H+:.*\)\|\(.*&&\\H+\\h.*\)\|\(.*!\\H+\\h.*\)\)' --md", 'options': ['--layout=default', '--info=inline'], 'prefix': mkdd#get_crusor_expression(), 'reducer': { lines ->  mkdd#references_reducer(lines[0])},}))

" inoremap <expr> <c-r> fzf#vim#complete(fzf#wrap({'source': "ag '^#\{1,2} \|title:' --md", 'prefix': '^.*$', 'reducer': { lines ->  mkdd#references_reducer(lines[0])},}))


" function to insert reference (similar to  zettel#fzf#sink_onefile(<q-args>, 'zettel#fzf#wiki_search'))
" (1) provide right search pattern to  zettel#fzf#sink_onefile
" (2) replace 'zettel#fzf#wiki_search' to output a full anchor and not file
" name only
" (3) done


" function to open file at reference (similar to zettel#fzf#sink_onefile(<q-args>, 'zettel#fzf#search_open'))
" (1) provide right search pattern to  zettel#fzf#sink_onefile
" (2) done

" ------------------------------------------------------------------------
