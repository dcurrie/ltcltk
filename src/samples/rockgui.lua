#!/usr/bin/env lua

--[[
 - rockgui
 -
 - a simple gui for luarocks, an example for 

 - Gunnar Zötl <gz@tset.de>, 2012.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

local APPTITLE = 'rockgui'

local ltk = require "ltk"

-- we need luarocks.api by Steve Donovan
local ok, api = pcall(require, 'luarocks.api')
if not ok then
	error("Luarocks.api is needed for this. You can get it from http://stevedonovan.github.com/files/luarocks-api-0.5-1.rockspec")
end

local ui = {}
local inst = {}
local all = {}


local function get_base_data()
	inst = api.list_map()
	all = api.search_map(nil, nil, {all = true})
end

local function sortedkeys(t)
	local res = {}
	local _, k, i
	i = 1
	for k, _ in pairs(t) do
		res[i] = k
		i = i + 1
	end
	table.sort(res)
	return res
end

local function clear()
	local c = ui.view:children('')
	if c ~= '' then
		ui.view:delete(unpack(c))
	end
end

local function display_data(what)
	local view = ui.view
	clear()
	
	local kys = sortedkeys(all)
	local k, v, _
	
	for _, k in ipairs(kys) do
		local isinst = inst[k] and 'installed ' .. inst[k].version or ''
		local n = view:insert{'', 'end', text=k, values = { isinst }}
		local desc = all[k]
		local ver
		for _, ver in ipairs(desc.versions) do
			view:insert{n, 'end', text=ver.version}
		end
	end
end

local function do_with_message(msg, func, ...)
	local t = ltk.toplevel()
	local m = ltk.message(t) {text=msg, width=100}
	m:pack()
	ltk.update()
	
	func(...)
	
	t:destroy()
end

local function select_entry()
	local sel = ui.view:selection()[1]
	local item = ui.view:item(sel, 'text')
	local data = all[item].info
	if not data then
		local d = api.search(item, nil, {details=true})
		data = d[1]
		all[item].info = data
	end
	local t = ui.text
	local k, v
	t:delete('0.0', 'end')
	for k, v in pairs(data) do
		t:insert('end', k, '\t', v, '\n')
	end
end

local function buildui()
	local fv = ltk.frame()
	local view = ltk.treeview (fv) { columns = {'status'}, selectmode='browse' }
	local sbv = ltk.scrollbar (fv) {['orient'] = "vert", command = function(...) view:yview(...) end}
	view.yscrollcommand = function(y1, y2) sbv:set(y1, y2) end
	sbv:pack {side='right', fill='y'}
	view:pack {expand=true, side='left', fill='both'}
	
	view:heading{'#0', text="Package"}
	view:heading{'status', text="Status"}

	view:bind('<<TreeviewSelect>>', select_entry)

	ui.view = view

	local ft = ltk.frame()
	local text = ltk.text(ft) ()
	local sbt = ltk.scrollbar (ft) {['orient'] = "vert", command = function(...) text:yview(...) end}
	text.yscrollcommand = function(y1, y2) sbt:set(y1, y2) end
	sbt:pack {side='right', fill='y'}
	text:pack {expand=true, side='left', fill='both'}
	
	ui.text = text
	
	fv:pack{side='left', fill='both'}
	ft:pack{side='right', fill='both'}

	ltk.update()
end

buildui()
do_with_message("Loading data...", get_base_data)
display_data()

ltk.mainloop()
