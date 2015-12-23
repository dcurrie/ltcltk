#!/usr/bin/env lua

--[[
 - ltkhello.lua
 -
 - a somewhat involved Hello World example.
 -
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
 -
 - 2011-10-12 adjusted for ltk version 2
--]]

ltk = require "ltk"

-- multipurpose destroy event handler, just displays some info.
function destroy(hash, t, T, W, X, i)
	print(string.format("destroy called, #='%s', t='%s', T='%s', W='%s', X='%s', i='%s'", hash, t, T, tostring(W), X, i))
end

-- create a button with a simple action that just terminates the program.
-- attach a destroy handler to it just for the sake of doing it
--
function finished()
	ltk.exit()
end

b = ltk.button()
-- the following could also have been an option for the creation of the button
b.text='OK'
b.command=finished

b:bind('<Destroy>', {destroy, '%#', '%t', '%T', '%W', '%X', '%i'})

-- create a text widget with a click handler, that inserts additional stuff.
-- also attach a destroy handler to it, again just for the sake of doing it
--
t = ltk.text {width=40, height=20}
function click(b, x, y)
	-- get insert position
	local pos = t:index('end')
	-- get char position
	local cpos = t:index('@'..x..','..y)
	t:insert(pos, string.format("click <%s> at %s\n", b, cpos))
end

t:bind('<Destroy>', {destroy, '%#', '%t', '%T', '%W', '%X', '%i'})
t:bind('<ButtonPress>', {click, '%b', '%x', '%y'})

-- add some initial text
t:insert('0.0', "Hello Lua!\n")

-- now for the layout, one under the other
t:grid {row=1}
b:grid {row=2}

-- attach a <Destroy> handler to the main window
ltk.stdwin:bind('<Destroy>', {destroy, '%#', '%t', '%T', '%W', '%X', '%i'})

-- and go.
ltk.mainloop()
