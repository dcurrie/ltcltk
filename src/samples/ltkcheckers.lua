#!/usr/bin/env lua

--[[
 - ltkcheckers.lua
 -
 - a simple checkers board with movable pieces
 - ported to lua+ltk from a piece of sample code on the tcl/tk wiki
 - http://wiki.tcl.tk/884
 -
 - Gunnar Zötl <gz@tset.de>, 2011.
 - Released under MIT/X11 license. See file LICENSE for details.
 -
 - 2011-10-12 adjusted for ltk version 2
--]]

ltk = require "ltk"

local dx = 50
local dy = 50
local colors = {'white', 'black', 'red', 'blue'}
local cx = 0
local cy = 0

-- the canvas on which we draw
c = ltk.canvas {width = dx * 8, height = dy * 8} 
c:pack()

-- handler for left-click event: mark position of click
function mark(x, y)
	cx = c:canvasx(x)
	cy = c:canvasy(y)
end

-- handler for drag event: move piece
function move(x, y)
	-- "current" is the piece we clicked on
    local id = c:find('withtag', 'current')
    x = c:canvasx(x)
    y = c:canvasy(y)
    c:move(id, x - cx, y - cy)
    c:raise(id)
    cx = x
    cy = y
end

-- handler for release event: snap to board
function drop()
	local id = c:find('withtag', 'current')
    local cx0 = math.floor(cx / dx) * dx + 2
    local cy0 = math.floor(cy / dy) * dy + 2
    local cx1 = cx0 + dx - 3
    local cy1 = cy0 + dy - 3
    c:coords(id, cx0, cy0, cx1, cy1)
end
 
c:itembind('mv', '<ButtonPress-1>', {mark, '%x', '%y'})
c:itembind('mv', '<B1-Motion>', {move, '%x', '%y'})
c:itembind('mv', '<ButtonRelease-1>', drop)

-- create a piece
function makepiece (x, y, color, args)
    c:create_oval {x+2, y+2, x+dx-3, y+dy-3, fill=color, tags={args, 'mv'}}
end

-- create a board field
function makecheck (x, y, color, args)
    c:create_rectangle {x, y, x+dx, y+dy, fill=color, tags={args}}
end

-- draw board and place pieces
color = 0
for i = 0, 7 do
	y = i * dy
    for j = 0, 7 do
		x = j * dx
		makecheck(x, y, colors[color])
		if i < 3 and color > 0 then
			makepiece(x, y, colors[2], 'player2')
		end
		if i > 4 and color > 0 then
			makepiece(x, y, colors[3], 'player1')
		end
		color = 1 - color
	end
    color = 1 - color
end

ltk.mainloop()
