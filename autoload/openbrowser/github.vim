" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}

let s:V = vital#of('open-browser-github.vim')
let s:Filepath = s:V.import('System.Filepath')


function! openbrowser#github#load()
    " dummy function to load this script.
endfunction

function! openbrowser#github#file(args) range
    let file = expand(empty(a:args) ? '%' : a:args[0])
    let gitdir = s:lookup_gitdir(file)
    call s:call_with_temp_dir(gitdir, 's:cmd_file', [a:args])
endfunction

function! s:cmd_file(args)
    let file = expand(empty(a:args) ? '%' : a:args[0])
    if !filereadable(file)
        if a:0 is 0
            call s:error("current buffer is not a file.")
        else
            call s:error("'".file."' is not readable.")
        endif
        return
    endif

    let user    = s:get_github_user()
    let repos   = s:get_github_repos_name()
    let branch  = s:get_repos_branch()
    let relpath = s:get_repos_relpath(file)
    let rangegiven = a:firstline isnot 1 || a:lastline isnot line('$')
    if rangegiven
        let lnum  = '#L'.a:firstline
        \          .(a:firstline is a:lastline ? '' : '-L'.a:lastline)
    else
        let lnum = ''
    endif

    if user ==# ''
        call s:error('github.user is not set.')
        call s:error("Please set by 'git config github.user yourname'.")
        return
    endif
    if repos ==# ''
        call s:error('Could not detect current repos name on github.')
        return
    endif
    if branch ==# ''
        call s:error('Could not detect current branch name.')
        return
    endif
    if relpath ==# ''
        call s:error('Could not detect relative path of repository.')
        return
    endif

    call s:open_github_url(
    \   '/'.user.'/'.repos.'/blob/'.branch.'/'.relpath.lnum)
endfunction

function! openbrowser#github#issue(args)
    let file = expand('%')
    let gitdir = s:lookup_gitdir(file)
    call s:call_with_temp_dir(gitdir, 's:cmd_issue', [a:args])
endfunction

function! s:cmd_issue(args)
    " '#1' and '1' are supported.
    let number = matchstr(a:args[0], '^#\?\zs\d\+\ze$')
    if number ==# ''
        call s:error("'".a:args[0]."' does not appear to be an issue number.")
        return
    endif

    let user  = s:get_github_user()
    let repos = s:get_github_repos_name()

    if user ==# ''
        call s:error('github.user is not set.')
        call s:error("Please set by 'git config github.user yourname'.")
        return
    endif
    if repos ==# ''
        call s:error('Could not detect current repos name on github.')
        return
    endif

    call s:open_github_url(
    \   '/'.user.'/'.repos.'/issues/'.number)
endfunction



function! s:call_with_temp_dir(dir, funcname, args)
    let haslocaldir = haslocaldir()
    let cwd = getcwd()
    if a:dir !=# '' && a:dir !=# cwd
        execute 'lcd' a:dir
    endif
    try
        return call(a:funcname, a:args)
    finally
        if a:dir !=# cwd
            execute (haslocaldir ? 'lcd' : 'cd') cwd
        endif
    endtry
endfunction

function! s:get_github_user()
    return s:git('config', '--get', 'github.user')
endfunction

function! s:get_github_repos_name()
    let host = s:get_github_host()
    let host_re = substitute(host, '\.', '\.', 'g')
    let ssh_re = 'git@'.host_re.':[^/]\+/\([^/]\+\)\s'
    let git_re = 'git://'.host_re.'/[^/]\+/\([^/]\+\)\s'
    let https_re = 'https\?://'.host_re.'/[^/]\+/\([^/]\+\)\s'

    for line in s:git_lines('remote', '-v')
        for re in [ssh_re, git_re, https_re]
            let m = matchlist(line, re)
            if !empty(m)
                return substitute(m[1], '\.git$', '', '')
            endif
        endfor
    endfor
    return ''
endfunction

function! s:get_repos_branch()
    let lines = s:git_lines('branch')
    let re = '\* '
    call filter(lines, 'v:val =~# re')
    if empty(lines)
        return ''
    endif
    let idx = matchend(lines[0], re)
    return idx >= 0 ? lines[0][idx :] : ''
endfunction

function! s:get_repos_relpath(file)
    let relpath = ''
    if s:is_relpath(a:file)
        let dir = s:git('rev-parse', '--show-prefix')
        let dir = dir !=# '' ? dir.'/' : ''
        let relpath = dir.a:file
    else
        let relpath = s:lookup_relpath_from_gitdir(a:file)
    endif
    let relpath = substitute(relpath, '\', '/', 'g')
    let relpath = substitute(relpath, '/\{2,}', '/', 'g')
    return relpath
endfunction

function! s:lookup_relpath_from_gitdir(path)
    return get(s:split_repos_path(a:path), 1, '')
endfunction

function! s:lookup_gitdir(path)
    return get(s:split_repos_path(a:path), 0, '')
endfunction

" Returns [gitdir, relative path] when git dir is found.
" Otherwise, returns empty List.
function! s:split_repos_path(dir, ...)
    let parent = s:Filepath.dirname(a:dir)
    let basename = s:Filepath.basename(a:dir)
    let removed_path = a:0 ? a:1 : ''
    if a:dir ==# parent
        " a:dir is root directory. not found.
        return []
    elseif s:is_git_dir(a:dir)
        return [a:dir, removed_path]
    else
        if removed_path ==# ''
            let removed_path = basename
        else
            let removed_path = s:Filepath.join(basename, removed_path)
        endif
        return s:split_repos_path(parent, removed_path)
    endif
endfunction

function! s:is_git_dir(dir)
    " .git may be a file when its repository is a submodule.
    let dotgit = s:Filepath.join(a:dir, '.git')
    return isdirectory(dotgit) || filereadable(dotgit)
endfunction

function! s:is_relpath(path)
    return a:path !=# '' && a:path[0] !=# '/'
endfunction

function! s:open_github_url(path)
    let endpoint = 'http://'.s:get_github_host()
    return openbrowser#open(endpoint.a:path)
endfunction

function! s:get_github_host()
    " Enterprise GitHub is supported.
    " ('hub' command is using this config key)
    let url = s:git('config', '--get', 'hub.host')
    return url !=# '' ? url : 'github.com'
endfunction



function! s:git(...)
    return s:trim(system(join(['git'] + a:000, ' ')))
endfunction

function! s:git_lines(...)
    let output = call('s:git', a:000)
    let keepempty = 1
    return split(output, '\n', keepempty)
endfunction



function! s:trim(str)
    let str = a:str
    let str = substitute(str, '^[ \t\n]\+', '', 'g')
    let str = substitute(str, '[ \t\n]\+$', '', 'g')
    return str
endfunction

function! s:error(msg)
    echohl ErrorMsg
    try
        echomsg 'openbrowser/github:' a:msg
    finally
        echohl None
    endtry
endfunction


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
