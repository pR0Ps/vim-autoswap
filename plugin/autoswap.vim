" Vim global plugin for automating response to swapfiles
" Maintainer: Gioele Barabucci
" Author:     Damian Conway
" License:    This is free software released into the public domain (CC0 license).

"#############################################################
"##                                                         ##
"##  Note that this plugin only works if your Vim           ##
"##  configuration does not override the `title` or         ##
"##  `titlestring` settings configured below.               ##
"##                                                         ##
"##  Note that this plugin uses window titles to find and   ##
"##  switch to windows. If the title for the file isn't set ##
"##  (ex: the unfocused buffer in a split) or is truncated  ##
"##  (ex: window isn't wide enough to fit the entire title) ##
"##  then switching to the window won't work.               ##
"##                                                         ##
"##  On MacOS this plugin only works fully for Vim sessions ##
"##  running in Apple Terminal or iTerm2. Other terminals   ##
"##  and GUI Vims are partially supported, but detecting    ##
"##  and switching to the active window will not work.      ##
"##                                                         ##
"##  On Linux this plugin requires the external program     ##
"##  wmctrl, packaged for most distributions.               ##
"##                                                         ##
"##                                                         ##
"##  To port this plugin to other operating systems         ##
"##                                                         ##
"##    1. Add s:detectWindow_<OS> and s:switchToWindow_<OS> ##
"##    2. Add a new elseif cases to s:detectWindow and      ##
"##       s:switchToWindow to call them.                    ##
"##                                                         ##
"#############################################################

if exists("loaded_autoswap")
	finish
endif
let loaded_autoswap = 1

" By default we don't try to detect tmux
if !exists("g:autoswap_detect_tmux")
	let g:autoswap_detect_tmux = 0
endif

" Preserve external compatibility options, then enable full vim compatibility
let s:save_cpo = &cpo
set cpo&vim

" Enable and set window titles to something we can parse
" If you change this you will also need to change the
" s:getWindowTitle function below
set title titlestring=%{expand(\"%:t\")}\ (%{expand(\"%:~:h\")})\ -\ VIM

" Gets the predicted window title based on the filename
function! s:getWindowTitle(filename)
	let relparent = fnamemodify(a:filename,":~:h")
	let name = fnamemodify(a:filename,":t")
	return name . ' ('.relparent.') - VIM'
endfunction


" Invoke the handling whenever a swapfile is detected
augroup autoswap
	autocmd!
	autocmd SwapExists * call s:handleSwapfile(expand('<afile>:p'), v:swapname)
augroup END

function! s:handleSwapfile(filename, swapname)

	" Is file already open in another Vim session in some other window?
	let active_window = s:detectWindow(a:filename, a:swapname)

	" If so, go there instead and terminate this attempt to open the file
	if (strlen(active_window) > 0)
		call s:showMsg('Switched to existing session in another window')
		call s:switchToWindow(active_window)
		let v:swapchoice = 'q'

	" Otherwise, if swapfile is older than file itself, just get rid of it
	elseif getftime(v:swapname) < getftime(a:filename)
		call s:showMsg('Old swapfile detected and deleted')
		call delete(v:swapname)
		let v:swapchoice = 'e'

	" Otherwise, open file read-only
	else
		call s:showMsg('Swapfile detected, opening read-only')
		let v:swapchoice = 'o'
	endif
endfunction


" Print a message after the autocommand completes
" (so you can see it, but don't have to hit <ENTER> to continue)
function! s:showMsg (msg)
	" A sneaky way of injecting a message when swapping into the new buffer
	augroup AutoSwap_Msg
		autocmd!
		" Print the message on finally entering the buffer
		autocmd BufWinEnter *  echohl WarningMsg
		exec 'autocmd BufWinEnter *  echon "\r'.printf("%-60s", a:msg).'"'
		autocmd BufWinEnter *  echohl NONE

		" And then remove these autocmds, so it's a "one-shot" deal
		autocmd BufWinEnter *  augroup AutoSwap_Msg
		autocmd BufWinEnter *  autocmd!
		autocmd BufWinEnter *  augroup END
	augroup END
endfunction


function! s:runningTmux ()
	if $TMUX != ""
		return 1
	endif
	return 0
endfunction

" Return an identifier for a terminal window already editing the file
" or an empty string if the window couldn't be found.
function! s:detectWindow (filename, swapname)
	if g:autoswap_detect_tmux && s:runningTmux()
		let active_window = s:detectWindow_Tmux(a:swapname)
	elseif has('macunix')
		let active_window = s:detectWindow_Mac(a:filename)
	elseif has('unix')
		let active_window = s:detectWindow_Linux(a:filename)
	endif
	return active_window
endfunction

" TMUX: Detection function for tmux, uses tmux
function! s:detectWindow_Tmux (swapname)
	let pid = systemlist('fuser '.a:swapname.' 2>/dev/null | grep -E -o "[0-9]+"')
	if (len(pid) == 0)
		return ''
	endif
	let tty = systemlist('ps -o "tt=" '.pid[0].' 2>/dev/null')
	if (len(tty) == 0)
		return ''
	endif
	let tty[0] = substitute(tty[0], '\s\+$', '', '')
	" The output of `ps -o tt` and `tmux-list panes` varies from
	" system to system.
	" * Linux: `pts/1`, `/dev/pts/1`
	" * FreeBSD: `1`, `/dev/vc/1`
	" * Darwin/macOS: `s001`, `/dev/ttys001`
	let window = systemlist('tmux list-panes -aF "#{pane_tty} #{session_id} #{window_index} #{pane_index}" | grep -F "'.tty[0].' " 2>/dev/null')
	if (len(window) == 0)
		return ''
	endif
	return window[0]
endfunction

" LINUX: Detection function for Linux, uses wmctrl
function! s:detectWindow_Linux (filename)
	let find_win_cmd = 'wmctrl -l | grep "'.s:getWindowTitle(a:filename).'" | tail -n1 | cut -d" " -f1'
	let active_window = system(find_win_cmd)
	return (active_window =~ '0x' ? active_window : "")
endfunction

" MAC: Detection function for Mac OSX, uses osascript
function! s:detectWindow_Mac (filename)
	if ($TERM_PROGRAM == 'Apple_Terminal')
		let find_win_cmd = 'osascript -e ''tell application "Terminal" to get the id of every window whose (name contains "'.s:getWindowTitle(a:filename).'")'''
	elseif ($TERM_PROGRAM == 'iTerm.app')
		let find_win_cmd = 'osascript -e ''tell application "iTerm2" to get the index of every window whose (name contains "'.s:getWindowTitle(a:filename).'")'''
	else
		return ''
	endif
	let active_window = system(find_win_cmd)
	let active_window = substitute(active_window, '^\d\+\zs\_.*', '', '')
	return (active_window =~ '\d\+' ? active_window : "")
endfunction


" Switch to the specified window
function! s:switchToWindow (active_window)
	if g:autoswap_detect_tmux && s:runningTmux()
		call s:switchToWindow_Tmux(a:active_window)
	elseif has('macunix')
		call s:switchToWindow_Mac(a:active_window)
	elseif has('unix')
		call s:switchToWindow_Linux(a:active_window)
	endif
endfunction

" TMUX: Switch function for Tmux
function! s:switchToWindow_Tmux (active_window)
	let pane_info = split(a:active_window)
	let session = pane_info[1]
	let window = pane_info[2]
	let pane = pane_info[3]
	call system("tmux select-window -t '".session.':'.window."'; tmux select-pane -t '".session.':'.window.'.'.pane."'")
endfunction

" LINUX: Switch function for Linux, uses wmctrl
function! s:switchToWindow_Linux (active_window)
	call system('wmctrl -i -a "'.a:active_window.'"')
endfunction

" MAC: Switch function for Mac, uses osascript
function! s:switchToWindow_Mac (active_window)
	if ($TERM_PROGRAM == 'Apple_Terminal')
		call system('osascript -e ''tell application "Terminal" to set frontmost of window id '.a:active_window.' to true''')
	elseif ($TERM_PROGRAM == 'iTerm.app')
		let switch_win_cmd = 'osascript -e ''tell application "iTerm"''
					\ -e ''repeat with mywindow in windows''
					\ -e ''   if index of mywindow is ' .a:active_window. '''
					\ -e ''     select mywindow''
					\ -e ''   return''
					\ -e ''   end if''
					\ -e '' end repeat''
					\ -e ''end tell'''
		call system(switch_win_cmd)
	endif
endfunction

" Restore previous external compatibility options
let &cpo = s:save_cpo

" vim: noexpandtab tabstop=4 softtabstop=4 shiftwidth=4
