#!/usr/bin/env lua

--[[
 - ltkbrowse.lua
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
 -
 - 2011-10-17 adjusted for ltk version 2
--]]

-- straight port of Tk8.5 widget example to ltk, original header follows:
--
--# browse --
--# This script generates a directory browser, which lists the working
--# directory and allows you to open files or subdirectories by
--# double-clicking.
--#
--# RCS: @(#) $Id: browse,v 1.5 2003/09/30 14:54:29 dkf Exp $

ltk = require "ltk"

-- very simple directory browser functions
local function trim(s)
	s = s or ''
	s = string.gsub(s, "^[%s%c]*", '')
	s = string.gsub(s, "[%s%c]*$", '')
	return s
end

function currentdir()
	local f = io.popen("pwd", "r")
	if f then
		local s = trim(f:read())
		f:close()
		return s
	end
end

function readdir(d)
	local f = io.popen("cd "..d.." && ls", "r")
	if f then
		local l, s = {}, nil
		s = f:read()
		while s do
			table.insert(l, trim(s))
			s = f:read()
		end
		f:close()
		return l
	end
end

function isdir(f)
	local f = io.popen("ls -ld "..f, "r")
	if f then
		local s = trim(f:read())
		f:close()
		return string.sub(s, 1, 1) == 'd'
	end
end

function isfile(f)
	local f = io.popen("ls -ld "..f, "r")
	if f then
		local s = trim(f:read())
		f:close()
		return string.sub(s, 1, 1) == '-'
	end
end

function islink(f)
	local f = io.popen("ls -ld "..f, "r")
	if f then
		local s = trim(f:read())
		f:close()
		return string.sub(s, 1, 1) == 'l'
	end
end

-- Create a scrollbar on the right side of the main window and a listbox
-- on the left side.

scroll = ltk.scrollbar {}
list = ltk.listbox {yscroll=function(...) scroll:set(...) end,
	relief="sunken", width=20, height=20, setgrid=true}
scroll.command=function(...) list:yview(...) end
scroll:pack{side='right', fill='y'}
list:pack{side='left', fill='both', expand='yes'}
ltk.stdwin:minsize(1, 1)

-- The procedure below is invoked to open a browser on a given file;  if the
-- file is a directory then another instance of this program is invoked; if
-- the file is a regular file then the Mx editor is invoked to display
-- the file.

if string.find(arg[0], '/') == 1 then
	browseScript=currentdir()..'/'..arg[0]
else
	browseScript=arg[0]
end
function browse(dir, file)
    file=dir..'/'..file
    if isdir(file) then
		os.execute("/usr/bin/env lua "..browseScript.." "..file.." &")
	elseif isfile(file) then
		if os.getenv("EDITOR") then
			os.execute(os.getenv("EDITOR").." "..file.." &")
		else
			os.execute("xedit "..file.." &")
		end
	else
			print("'"..file.."' isn't a directory or regular file")
	end
end

-- Fill the listbox with a list of all the files in the directory.

if #arg>0 then
	dir=arg[1]
else
	dir="."
end
files = readdir(dir)
for _,i in ipairs(files) do
    if isdir(dir..'/'..i) then
		i = i .. '/'
    end
    list:insert('end', i)
end

-- Set up bindings for the browser.
-- strangely enough, binding to 'all' throws an error, eventhough when doing it
-- through ltk.tcl:eval(), it works... No problem, as binding to '.' does the
-- same thing when there is only one window.
ltk.bind('all', '<Control-c>', ltk.exit)
list:bind('<Double-Button-1>', function()
		local n = list:curselection()
		browse(dir, list:get(n))
	end)

ltk.mainloop()
