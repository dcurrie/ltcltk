#!/usr/bin/env lua

--[[
 - ltkfuncplotter.lua
 -
 - simple function plotter, sample for ltk
 -
 - This is not intended to be a first class function plotter app, just
 - to provide a starter on how to use ltk.
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
 -
 - 2011-10-12 adjusted for ltk version 2
--]]

ltk = require "ltk"

-- application window title
apptitle = "ltk Function Plotter"

-- filetypes we use
myfiletype = {{{'LtkFuncplotter'}, {'.func'}}}
psfiletype = {{{'PostScript'}, {'.ps'}}}

-- widgets. for the canvas widget, we create a widget command function in order
-- to make it more easily usable.
canvas = ltk.canvas {background='white'}
-- this is the menu bar
bar = ltk.menu {['type']='menubar'}
-- other ui widgets
lxmin = ltk.label {text="Minimum x"}
xmin = ltk.entry {background='white'}
lxmax = ltk.label {text="Maximum x"}
xmax = ltk.entry {background='white'}
lymin = ltk.label {text="Minimum y"}
ymin = ltk.entry {background='white'}
lymax = ltk.label {text="Maximum y"}
ymax = ltk.entry {background='white'}
lfunc = ltk.label {text="Function(x)"}
func = ltk.entry {background='white', text='x'}
plot = ltk.button {text="Plot"}

-- the environment in which functions will be evaluated.
local fenv = {}
for name, func in pairs(math) do fenv[name] = func end

-- evaluate the function passed as a string for one value
function evaluate(func, x)
	local f = loadstring("return "..func)
	fenv['x'] = x
	setfenv(f, fenv)
	local ok, val = pcall(f)
	if ok then return val else return ok, val end
end

-- check wether the passed arguments are sensible for the function plotter
function validate_data(xmin, xmax, ymin, ymax, func)
	local msg = ""
	if xmin==nil then
		msg = msg .. 'Minimum X must be a number\n'
	end
	if xmax==nil then
		msg = msg .. 'Maximum X must be a number\n'
	end
	if ymin==nil then
		msg = msg .. 'Minimum Y must be a number\n'
	end
	if ymax==nil then
		msg = msg .. 'Maximum Y must be a number\n'
	end
	if xmin and xmax and xmin >= xmax then
		msg = msg .. 'Minimum X must be less than maximum X\n'
	end
	if ymin and ymax and ymin >= ymax then
		msg = msg .. 'Minimum Y must be less than maximum Y\n'
	end
	if func == nil then
		msg = msg .. 'You must specify a function\n'
	else
		local val, m = evaluate(func, xmin)
		if not val then
			msg = msg .. 'The function returned an error:\n  '..m
		end
	end

	if msg ~= "" then
		ltk.messageBox{title='Error', message=msg, ['type']='ok'}
	end

	return msg == ""
end

-- draw coordinate system and also compute scale factors and origin
function drawcoords(xmin, xmax, ymin, ymax)
	local cw = ltk.winfo.width(canvas)
	local ch = ltk.winfo.height(canvas)
	local pw = cw - 30
	local ph = ch - 30

	local xfac = pw / (xmax-xmin)
	local yfac = ph / (ymax - ymin)
	local fac = (xfac < yfac) and xfac or yfac

	local w = fac * (xmax - xmin)
	local h = fac * (ymax - ymin)
	local x0 = (cw - w) / 2
	local y0 = (ch - h) / 2

	-- draw graph decorations and annotations
	canvas:create_rectangle {x0, y0+h, x0+w, y0 }
	canvas:create_text {x0-2, y0, text=ymax, anchor='ne'}
	canvas:create_text {x0-2, y0+h, text=ymin, anchor='se'}
	canvas:create_text {x0, y0+h+2, text=xmin, anchor='nw'}
	canvas:create_text {x0+w, y0+h+2, text=xmax, anchor='ne'}

	if xmin<0 and xmax>0 then
		local x_0 = -xmin * fac + x0
		canvas:create_line {x_0, y0, x_0, y0+h, fill='#ff0000'}
	end

	if ymin<0 and ymax>0 then
		local y_0 = -ymin * fac + y0
		canvas:create_line {x0, y_0, x0+w, y_0, fill='#ff0000'}
	end

	-- return origin and scales.
	return x0, w, y0+h, -h
end

-- plot the function. Values are read from the widgets by means of their widget
-- command 'get'.
function do_plot()
	local xmin = tonumber(xmin:get())
	local xmax = tonumber(xmax:get())
	local ymin = tonumber(ymin:get())
	local ymax = tonumber(ymax:get())
	local func = func:get()

	if not validate_data(xmin, xmax, ymin, ymax, func) then return end

	-- clear canvas
	canvas:delete('all')
	-- add name of function we plot
	canvas:create_text {1, 1, text="Function: "..func, anchor='nw'}

	-- and draw the function
	local x0, w, y0, h = drawcoords(xmin, xmax, ymin, ymax)
	local fx = (xmax - xmin) / w
	local fy = h / (ymax- ymin)
	local py = (evaluate(func, xmin) - ymin) * fy + y0
	local x,y
	for x = x0+1, x0+w do
		y = (evaluate(func, (x-x0)*fx+xmin) - ymin) * fy + y0
		canvas:create_line {x-1, py, x, y, fill='#0000ff'}
		py = y
	end
end

-- helper function, as setting values for entry widgets is a bit involved.
function setval(widget, val)
	local v = widget:get()
	local lv = #v or 0
	widget:delete(0, lv)
	widget:insert(0, tostring(val))
end

-- load a function plot definition from a file
function open()
	local file = ltk.getOpenFile{filetypes=myfiletype}
	-- an empty string is returned if the openfile dialog is aborted
	if file == "" then return end
	local f, err = loadfile(file)
	if f == nil then error(err) end
	local name, val
	local args = f()
	for name, val in pairs(args) do
		widget = _G[name]
		setval(widget, val)
	end

	-- set window title with file name
	ltk.stdwin:title(apptitle .. ': ' .. file)
end

-- save current function plot definition to a file.
function save()
	local file = ltk.getSaveFile{filetypes=myfiletype}
	-- an empty string is returned if the savefile dialog is aborted
	if file == "" then return end
	local f = io.open(file, 'w')
	local name, widget, idx, val
	f:write("return {")
	for idx, name in pairs {'xmin', 'xmax', 'ymin', 'ymax', 'func'} do
		if idx > 1 then f:write(",\n") else f:write("\n") end
		widget = _G[name]
		val = widget:get()
		f:write(string.format('["%s"]="%s"', name, tostring(val)));
	end
	f:write("\n}\n")
	f:close()

	-- set window title with file name
	ltk.stdwin:title(apptitle .. ': ' .. file)
end

-- save the current graph as postscript file. The canvas widget directly
-- supports this.
function savegraph()
	local gfile = ltk.getSaveFile{filetypes=psfiletype}
	-- an empty string is returned if the openfile dialog is aborted
	if gfile == "" then return end
	canvas:postscript {file=gfile}
end

-- create the application menu and submenu
function buildmenu()
	-- submenu "File"
	local file = ltk.menu {title='File'}
	
	file:add {'command', label='Open...', command=open }
	file:add {'command', label='Save...', command=save }
	file:add {'command', label='Save Graph', command=savegraph }
	file:add {'separator'}
	file:add {'command', label='Quit', command=ltk.exit}

	-- now add submenu to main menu
	bar:add {'cascade', menu=file, label='File' }
end

-- build the application window. We use a grid layout, and sticky the widgets
-- in order to make them behave sensibly when the window resizes.
function buildwin()
	buildmenu()
	ltk.stdwin.menu=bar
	
	plot.command = do_plot

	xmin:insert(0, 0)
	xmax:insert(0, 1)
	ymin:insert(0, 0)
	ymax:insert(0, 1)
	func:insert(0, 'x')

	-- we sticky the entry widgets at their left and right sides, so that they
	-- will only grow wider, not higher.
	lxmin:grid {column=0, row=0}
	xmin:grid {column=1, row=0, sticky='we'}
	lxmax:grid {column=0, row=1}
	xmax:grid {column=1, row=1, sticky='we'}
	lymin:grid {column=2, row=0}
	ymin:grid {column=3, row=0, sticky='we'}
	lymax:grid {column=2, row=1}
	ymax:grid {column=3, row=1, sticky='we'}
	lfunc:grid {column=4, row=0}
	func:grid {column=5, row=0, columnspan=2, sticky='we'}
	plot:grid {column=6, row=1, sticky='we'}

	-- the canvas widget should fill the entire space, so we sticky it on all
	-- 4 sides.
	canvas:grid {row=2, columnspan=7, sticky='nwse'}

	-- now tell the layout manager how to resize the widgets. Labels should not
	-- be resized, entry and canvas widgets should.
	ltk.grid.columnconfigure {'.', 1, weight=1}
	ltk.grid.columnconfigure {'.', 3, weight=1}
	ltk.grid.columnconfigure {'.', 5, weight=1}
	ltk.grid.columnconfigure {'.', 6, weight=1}
	ltk.grid.rowconfigure {'.', 2, weight=1}
end

-- now create the application window
ltk.tk.appname(apptitle)
buildwin()

ltk.bind('all', '<Return>', do_plot)

-- and run the app. This never returns.
ltk.mainloop()
