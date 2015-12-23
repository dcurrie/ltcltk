--[[
 - ltk.lua
 -
 - bind tk gui toolkit to lua
 -
 - Gunnar Zötl <gz@tset.de>, 2010, 2011, 2012.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

--[[ TODO
	-text.search
	-notebook.tab
	-panedwindow.pane
	-configure output
	-winfo & possibly wm
	-optionen immer in separatem table
--]]

-- references to global functions
local _
local t_insert = table.insert
local t_remove = table.remove
local t_concat = table.concat
local t_unpack = unpack or table.unpack
local s_gsub = string.gsub
local s_find = string.find
local s_format = string.format
local s_sub = string.sub
local s_gmatch = string.gmatch
local os_exit = os.exit
local setmetatable = setmetatable
local getmetatable = getmetatable
local pairs = pairs
local ipairs = ipairs
local type = type
local select = select
local tostring = tostring
local error = error
local pcall = pcall
local rawget = rawget
local rawset = rawset
local stderr = io.stderr
local ltcl = require "ltcl"

-- DEBUG STUFF

local print=print
local function vprint(...)
	local function fixval(v)
		if type(v) == 'string' then
			return "'"..v.."'"
		else
			return tostring(v)
		end
	end

	local i, val
	for i = 1, select('#', ...) do
		val = select(i, ...)
		if type(val) == 'table' then
			local k, v
			print(tostring(val) .. ' = {')
			for k, v in pairs(val) do
				local ks = tostring(k)
				print("  ["..fixval(k).."] = " .. fixval(v))
			end
			print('}')
		else
			print(tostring(val))
		end
	end
end

-- END DEBUG STUFF

local _M = {}
_M._VERSION = 1.9
_M._REVISION = 3

-- initialize ltk state
--
local tcl_interp = ltcl.new()
local ltcl_call = ltcl.call
local ltcl_callt = ltcl.callt
_M.tcl = tcl_interp
_M._TKVERSION = tcl_interp:eval 'package require "Tk"'

-- this will be set as metatable for widgets, helps to id them as such
local ltk_widget_id = 'ltk_widget'

-- store for all created widgets. Widgets will be entered here upon creation
-- and deleted when they're destroyed.
local widgets = {}

-- cache for lua functions to be registered with the tcl interpreter
local func_cache = setmetatable({}, {__mode='v'})	-- use with care

-- cache for configuration options per widget type. An entry for each
-- type is created when a widget of a type is first instantiated.
local widget_options_cache = {}

-- cache for widget commands per widget type
local widget_command_cache = {}

-- pseudo widget for "all widgets"
local all_widgets = {
	_id = 'all',
	_registered = {},
	_destroyfns = {}
}

-- set of utility functions to call into tcl, marking an error where the
-- function that called this function was called.
local function tcl_call(...)
	local ok, val = pcall(ltcl_call, tcl_interp, ...)
	if not ok then
		error(val, 3)
	end
	return val
end

local function tcl_callt(...)
	local ok, val = pcall(ltcl_callt, tcl_interp, ...)
	if not ok then
		error(val, 3)
	end
	return val
end

-- special table of old style widgets, not supporting some modern features,
-- and thus needing special treatment e.g. für state/instate
--
local antique_widgets = {
	canvas = true,
	listbox = true,
	menu = true,
	message = true,
	spinbox = true,
	text = true
}
local function is_antique_widget(w)
	return w and w._type and antique_widgets[w._type]
end

-- genid
--
-- utility function to generate unique widget id within tk state
--
local ltk_id_count = 0
local function genid()
	ltk_id_count = ltk_id_count + 1
	return s_format(".ltkid%08x", ltk_id_count)	
end

-- genvar
--
-- utility function to generate a unique variable name within tk state
--
local ltk_var_count = 0
local function genvar()
	ltk_var_count = ltk_var_count + 1
	return s_format("ltkvar%08x", ltk_var_count)	
end

-- create variable passthru table
-- calling it creates a new unique variable within the tcl interpreter and
--  returns its name
-- using it as an array sets or reads the variable corresponding to the index
-- on the tcl interpreter
--
_M.var = setmetatable({}, {
	__call = function()
		local v = genvar()
		tcl_interp:setvar(v, '')
		return v
	end,

	__index = function(_, idx)
		local ok, val = pcall(ltcl.getvar, tcl_interp, idx)
		return ok and val or nil
	end,

	__newindex = function(_, idx, val)
		return tcl_interp:setvar(idx, val)
	end
})

-- mkset
--
-- utility function to turn a list into a set
-- creates a hash table from the array part of the argument, the hash part is
-- copied as is
--
-- Arguments:
--	l	list to create a set from
--
-- Returns:
--	a set created from the list by the above rules
--
local function mkset(l)
	local k, v
	local s = {}
	for k, v in pairs(l) do
		if type(k) == 'number' then
			s[v] = v
		else
			s[k] = v
		end
	end
	return s
end

-- mklist
--
-- utility function to return a list of the keys from any tables
--
local function mklist(...)
	local s, n
	local k, v
	local l, i = {}, 1
	for n = 1, select('#', ...) do
		s = select(n, ...)
		for k, v in pairs(s) do
			l[i] = k
			i = i + 1
		end
	end
	return l
end

-- registerfunc
--
-- utility function to register lua functions with tk
-- checks wether the argument is
-- - a lua function. if so, registers it with the tcl interpreter
-- - a table, in that case the first element must be a function to be treated
--   like above, or a string, and the rest
--   are arguments, all of this is concatenated to a list
-- In these cases the function returns the generated id (or nil if no id was
-- generated) and the command to pass to a function or widget option, otherwise
-- returns nil
--
-- Arguments:
--	func	function to register with the tk state
--
local function registerfunc(func)
	local id, cmd
	if type(func) == 'function' then
		id = genvar()
		tcl_interp:register(id, func)
		func = id
	elseif type(func) == 'table' then
		if type(func[1]) == 'function' then
			id = genvar()
			tcl_interp:register(id, func[1])
			func[1] = id
		end
	else
		id = nil
	end
	return id, func
end

-- getcachedfuncid
--
-- utility function to retrieve a cached function id, or if it is not cached,
-- generate a new id and cache and return that.
--
-- Arguments:
--	fn	function to get id for
--
local function getcachedfuncid(fn)
	local id
	if func_cache[fn] ~= nil then
		id = func_cache[fn]
	else
		id = genvar() --genid()
		tcl_interp:register(id, fn)
		func_cache[fn] = id
	end
	return id
end

----- generic widget handling stuff -----

-- destroywidget
--
-- utility function to unregister any functions associated with a widget and
-- invalidate its state.
-- Note: once a widget has been destroyed, you can not use it again!
--
-- Arguments:
--	tk	tk state
--	wid	id of widget that is to be destroyed
--	hash, t, T, W	%#,%t,%T,%W from the Tcl event, see Tcl function "bind" doc
--
local function destroywidget(wid, hash, t, T, W)
	local widget = widgets[wid]
	-- this may happen when destroywidget is called on application shutdown or
	-- if the destroy event trickles up a child-parent widget chain.
	if (not widget) or (wid ~= W) then return end
	-- call registered <Destroy> handlers
	local destroyfns = widget._destroyfns or {}
	for i=1, #destroyfns do
		local fn = destroyfns[i]
		if type(fn) == 'function' then
			fn()
		elseif type(fn) == 'table' then
			local i
			local f = fn[1]
			local args = {}
			for i = 2, #fn do
				local v = fn[i]
				if v == '%W' then
					args[i-1] = widgets[W]
				else
					v = s_gsub(v, '%%#', hash or '??')
					v = s_gsub(v, '%%t', t or '??')
					v = s_gsub(v, '%%T', T or '??')
					v = s_gsub(v, '%%W', tostring(widgets[W]) or '??') -- if %W occurs within a string
					v = s_gsub(v, '%%%a', '??')
					args[i-1] = s_gsub(v, '%%%%', '%')
				end
			end
			-- the handler needs to be pcalled or else an error in the handler would
			-- not be flagged.
			local ok, err = pcall(f, t_unpack(args))
			if not ok then
				error(err)
				os.exit()
			end
		end
	end
	for i=1, #widget._registered do
		tcl_interp:unregister(widget._registered[i])
	end
	widgets[wid] = nil
end 

-- make a Tk usable argument list from the arguments passed to the function
--	- if the is only one argument and it is a table, return a ltcl_interp:makearglist()ed
--	  version of the table
--	- otherwise return a ltcl_interp:makearglist()ed version of the arguments packed
--	  into a table
-- if you need option arguments to your function, then the argument list has to be a table.
--
local function mkarglist_r(reg, ...)
	local a1 = select(1, ...)
	local na = select('#', ...)
	local doreg = (type(reg) == 'table')
	local res
	if na == 1 and type(a1) == 'table' and getmetatable(a1) ~= ltk_widget_id then
		res = tcl_interp:makearglist(a1)
	else
		res = {...}
	end
	
	-- now fix args: replace widgets by widget id's
	-- register any functions and replace them by their id's
	-- register any widgets and replace them by their id's
	local i, v
	for i, v in ipairs(res) do
		local t = type(v)
		if t == 'function' then
			res[i] = getcachedfuncid(v)
			if doreg then t_insert(reg, res[i]) end
		elseif t == 'table' then
			if getmetatable(v) == ltk_widget_id then
				res[i] = v._id
			elseif type(v[1]) == 'function' then
				v[1] = getcachedfuncid(v[1])
				if doreg then t_insert(reg, v[1]) end
			end
		end
	end
	
	return res
end

local function mkarglist(...)
	return mkarglist_r(false, ...)
end

-- utility function to extract available options from a widget and cache them
--
local function cache_widget_options(wid, n)
	if widget_options_cache[n] == nil then
		local t = tcl_call(wid, 'configure')
		if type(t) == 'string' then t = tcl_interp:list2table(t) end
		if type(t) ~= "table" then panic() end
		local entry = {}
		local v
		
		for _, v in ipairs(t) do
			if type(v) == 'string' then
				-- these happen if configure returned a string that needed to
				-- be hacked apart by list2table
				local lv, s = {}, nil
				for s in s_gmatch(v, "([^%s]+)") do t_insert(lv, s) end
				v = lv
			end
			local nm = s_sub(v[1], 2)
			-- weed out state compatibility option
			if nm ~= "state" then
				entry[nm] = v[4]
			end
		end
		
		widget_options_cache[n] = entry
	end
end

-- widget methods that are not standard tk or must be changed to work here

local widget_methods = {}

-- configure method. This needs some special treatment so it is all wrapped up
-- in a lua function
--
local function fix_config_row(r)
	if type(r) == 'string' then
		r = tcl_interp:list2table(r)
	end
	local res = {
		s_sub(r[1], 2),
		r[4],
		r[5]
	}
	return res
end

function widget_methods.configure(wid, ...)
	local nargs = select('#', ...)
	local farg = select(1, ...)
	if nargs == 0 then
		local c = tcl_call(wid._id, 'configure')
		if type(c) == 'string' then c = tcl_interp:list2table(c) end
		local i, r
		for i, r in ipairs(c) do
			c[i] = fix_config_row(r)
		end
		return c
	elseif nargs == 1 and type(farg) == 'string' then
		local c = tcl_call(wid._id, 'configure', '-'..farg)
		return fix_config_row(c)
	else
		local args = mkarglist_r(wid._registered, ...)
		return tcl_callt(wid._id, 'configure', args)
	end
end

function widget_methods.cget(wid, option)
	return tcl_call(wid._id, 'cget', '-'..option)
end

-- Tk functions repacked as methods to call on a widget

-- pack geometry function
--
function widget_methods.pack(wid, ...)
	local args = mkarglist(...)
	return tcl_callt('pack', wid._id, args)
end

-- grid geometry function
--
function widget_methods.grid(wid, ...)
	local args = mkarglist(...)
	return tcl_callt('grid', wid._id, args)
end

-- place geometry function
--
function widget_methods.place(wid, ...)
	local args = mkarglist(...)
	return tcl_callt('place', wid._id, args)
end

-- system clipboard interacion functions
--
function widget_methods.textcopy(wid)
	return tcl_call('tk_textCopy', wid._id)
end

function widget_methods.textcut(wid)
	return tcl_call('tk_textCut', wid._id)
end

function widget_methods.textpaste(wid)
	return tcl_call('tk_textPaste', wid._id)
end

-- tk bind function
function widget_methods.bind(wid, ...)
	return _M.bind(wid, ...)
end

-- tk bindtags function
--
function widget_methods.bindtags(wid, ...)
	local args = mkarglist(...)
	local res = tcl_callt('bindtags', wid._id, args)
	local n
	for n = 1, #res do
		local rn = res[n]
		res[n] = widgets[rn] or rn
	end
	return res
end

-- helper for state methods
--
local function fix_single_state(is_antique, s)
	if is_antique then
		if s == '!normal' then
			return 'disabled'
		elseif s == '!disabled' then
			return 'normal'
		end
	else
		if s == '!normal' then
			return 'disabled'
		elseif s == 'normal' then
			return '!disabled'
		end
	end
	return s
end

-- unify old style and new style state names
-- 
local function fix_statespec(is_antique, state)
	local news
	if state == nil then return nil end

	if type(state) == 'string' then
		news = fix_single_state(is_antique, state)
	elseif is_antique then
		if #state > 1 then
			error("Too many states", 2)
		end
		news = fix_single_state(is_antique, state[1])
	else
		local _, s
		news = {}
		for _, s in ipairs(state) do
			news[_] = fix_single_state(is_antique, s)
		end
	end
	return news
end

-- state method
--
function widget_methods.state(wid, s)
	local antiq = is_antique_widget(wid)
	local invs
	
	s = fix_statespec(antiq, s)
	if is_antique_widget(wid) then
		if s then
			tcl_call(wid._id, 'configure', '-state', s)
			invs = (s == 'normal') and 'disabled' or 'normal'
		else
			invs = tcl_call(wid._id, 'cget', '-state')
		end
	else
		if s then
			invs = tcl_call(wid._id, 'state', s)
		else
			invs = tcl_call(wid._id, 'state')
			if invs == '' then invs = 'normal' end
		end
	end
	return tcl_interp:list2table(invs)
end

-- instate method
--
function widget_methods.instate(wid, s)
	local antiq = is_antique_widget(wid)
	local res

	s = fix_statespec(antiq, s)
	if antiq then
		res = tcl_call(wid._id, 'cget', '-state')
		res = (res == s)
	else
		res = tcl_call(wid._id, 'instate', s) == 1
	end
	return res
end

-- tk destroy function
-- ltk specific cleanup is handled by the widgets <Destroy> event handlers
--
function widget_methods.destroy(wid)
	return tcl_call('destroy', wid._id)
end

-- options method
-- returns a list of supported configuration options for a widget
-- Note: this returns a copy of the actual list in order to protect the innocent
--
function widget_methods.options(wid)
	local c = widget_options_cache[wid._type]
	return mklist(c)
end

-- options method
-- returns a list of supported configuration options for a widget
-- Note: this returns a copy of the actual list in order to protect the innocent
--
function widget_methods.methods(wid)
	local c = widget_command_cache[wid._type]
	return mklist(widget_methods, c)
end

-- metamethods for widget handling
--
-- tostring returns a string representation of the widget
local function handle_tostring(wid)
	return "ltk_widget<" .. wid._type .. ">: " .. wid._id
end

-- index function: if called with a config option, then cget is called with
-- that option and the valueq is returned, otherwise a closure is returned to
-- call a widget method
--
local function handle_index(wid, i)
	local wmi = widget_methods[i]
	if wmi ~= nil then
		return wmi
	end
	local wtype = rawget(wid, '_type')

	local cmdc = widget_command_cache[wtype]
	local cmd = cmdc and cmdc[i]
	if cmd then
		local tcmd = type(cmd)
		local w_id = rawget(wid, '_id')
		local _r = rawget(wid, '_registered')
		if tcmd == 'function' then
			return cmd
		elseif tcmd == 'string' then
			cmdc[i] = function(wid, ...)
				return tcl_callt(wid._id, cmd, mkarglist_r(_r, ...))
			end
		elseif tcmd == 'table' then
			local cmd, scmd = t_unpack(cmd)
			cmdc[i] = function(wid, ...)
				return tcl_callt(wid._id, cmd, scmd, mkarglist_r(_r, ...))
			end
		end
		return cmdc[i]
	else
		local cfg = widget_options_cache[wtype]
		if cfg and cfg[i] then
			return tcl_call(wid._id, 'cget', '-'..i)
		else
			error('unknown option or method "'..i..'"', 2)
		end
	end
end

-- newindex function: we can only set config options, so configure is always called here.
local function handle_newindex(wid, i, v)
	local tv = type(v)
	local id
	-- fix value if needed
	if tv == 'function' then
		id = getcachedfuncid(v)
		v = id
	elseif getmetatable(v) == ltk_widget_id then
		v = v._id
	elseif tv =='table' and type(v[1]) == 'function' then
		id = getcachedfuncid(v[1])
		v[1] = id
	end
	tcl_call(wid._id, 'configure', '-'..i, v)
	if id ~= nil then t_insert(wid._registered, id) end
end

-- widget
--
-- generic widget creation function
-- creates a new widget of the type specified by the name parameter, and
-- registers a <Destroy> event handler for it to do housekeeping when the
-- widget is destroyed. The function returns the called widget id.
--
-- Arguments:
--	wtype	type of widget to be created
--	tname	name of ltk widget type
--	opts	table of arguments for object creation
--	passedid you may create a hollow widget, that is, a table that behaves like
--		a widget but is not actually linked to tk, if you specify the pathname
--		yourself.
--
local function create_widget(wtype, tname, opts, passedid, parent)
	opts = opts or {}
	tname = tname or wtype
	local pathname = passedid
	local parentid
	if getmetatable(parent) == ltk_widget_id then
		parentid = parent._id
	end
	if parentid == '.' or not parentid then
		parentid = ''
	end

	if pathname == nil then
		pathname = parentid .. genid()
		tcl_callt(wtype, pathname, opts)
	else
		pathname = parentid .. pathname
	end

	local widget = {
		_id = pathname,
		_type = tname,
		_registered = {},
		_destroyfns = {}
	}
	
	setmetatable(widget, {
		__tostring = handle_tostring,
		__index = handle_index,
		__newindex = handle_newindex,
		__metatable = ltk_widget_id
	})
	widgets[pathname] = widget

	-- if we create a hollow widget, we don't register a destroy handler for it.
	-- also, as it doesn't have a type, we don't retrieve its widget type options
	if passedid == nil then
		cache_widget_options(pathname, tname)

		_M.bind(widget, '<Destroy>',
			{ function(...) destroywidget(pathname, ...) end,
				'%#', '%t', '%T', '%W' })
	end
	
	return pathname, widget
end

-- makewidget
--
-- create and register a tk widget creation function. Takes care of all prepa-
-- rations for later invocations like fixing function args and such
--
-- Arguments:
--	wtype	tk widget type to create function for, will also be the name of the
--			widget creation function within ltk, unless mname is specified.
--	tname	if specified, the new widget creation function will be registered
--			under this name
--	cmds	widgets commands that may have functions in their argument list,
--			and the table of arguments to them that may be functions.
--
local function makewidget(wtype, tname, cmds)
	tname = tname or wtype
	cmds = cmds or {}
	widget_command_cache[tname] = mkset(cmds)
	
	-- constructor, may be called as func{opts} or func(parent){opts}
	return function(opts)
		opts = opts or {}
		local pfx
		local fn = function(...)
			local reg = {}
			local opts = mkarglist_r(reg, ...)
			local wid, widget = create_widget(wtype, tname, opts, nil, pfx)
			rawset(widget, '_registered', reg)
			return widget
		end
		if opts._id and opts._type then
			pfx = opts
			return fn
		else
			return fn(opts)
		end
	end
end

-- helper functions for argument list handling

-- fix_optvallist
--
-- converts lists of the form {'-option', 'value', '-option2', 'value', ...}
-- to { option=value, option2=value, ...}
--
local function fix_optvallist(list)
	local res = {}
	local i, n = 1, #list
	while i <= n do
		res[s_sub(list[i], 2)] = list[i+1]
		i = i + 2
	end
	return res
end

-- fix_switches
--
-- converts tables of the form {option1, option2=true, option3=false, option4=somevalue}
-- to a list of the form {'-option1', '-option2', '-option4', somevalue}
--
local function fix_switches(sw)
	local res = {}
	local k, v
	local i = 1
	for k, v in pairs(sw) do
		if type(k) == 'number' then
			k = v
			v = true
		end
		if v then
			res[i] = '-'..k
			i = i + 1
		end
		if type(v) == 'function' then
			res[i] = getcachedfuncid(v)
			i = i + 1
		elseif v and v ~= true then
			res[i] = v
			i = i + 1
		end
	end
	return res
end

-- end helper functions

local function mkitemcmd(cmd, cmdlen, ...)
	local mcmd = { t_unpack(cmd) }
	local i, k, n = cmdlen + 1, 1, select('#', ...)
	while k <= n do
		mcmd[i] = select(k, ...)
		i = i + 1
		k = k + 1
	end
	return mcmd
end

local function mkitemcgetfunc(...)
	local cmd = {...}
	local cmdlen = select('#', ...)

	return function(wid, idx, option)
		return tcl_callt(wid._id, mkitemcmd(cmd, cmdlen, idx, '-'..option))
	end
end

local function mkitemconfigurefunc(...)
	local cmd = {...}
	local cmdlen = select('#', ...)

	return function (wid, item, ...)
		local nargs = select('#', ...)
		local farg = select(1, ...)
		if nargs == 0 and type(item) ~= 'table' then
			local c = tcl_callt(wid._id, mkitemcmd(cmd, cmdlen, item))
			if type(c) == 'string' then c = tcl_interp:list2table(c) 
			end
			local i, r
			for i, r in ipairs(c) do
				c[i] = fix_config_row(r)
			end
			return c
		elseif nargs == 1 and type(farg) == 'string' then
			local c = tcl_callt(wid._id, mkitemcmd(cmd, cmdlen, item, '-'..farg))
			return fix_config_row(c)
		else
			local args = mkarglist_r(wid._registered, item)
			return tcl_callt(wid._id, mkitemcmd(cmd, cmdlen, t_unpack(args)))
		end
	end
end

local function mkoptionsfunc(name)
	return function(wid, ...)
		local arg
		local a1 = select(1, ...)
		local narg = select('#', ...)
		local res

		if narg == 1 and type(a1) == 'table' then
			narg = 0
			arg = a1
		else
			arg = {...}
		end

		if narg == 0 then
			return tcl_callt(wid._id, name, mkarglist(arg))
		elseif narg == 2 then
			return tcl_callt(wid._id, name, a1, '-' .. arg[2])
		else
			local r0 = tcl_callt(wid._id, name, a1)
			return fix_optvallist(r0)
		end
	end
end

local function mkpreoptionsfunc(name)
	return function(wid, ...)
		local narg = select('#', ...)
		local lastarg = select(narg, ...)
		local arg = {}
		if type(lastarg) == 'table' and getmetatable(lastarg) ~= ltk_widget_id then
			arg = fix_switches(lastarg)
			narg = narg - 1
		end
		local i, k = 1, #arg + 1
		for i=1, narg do
			arg[k] = select(i, ...)
			k = k + 1
		end
		return tcl_callt(wid._id, name, arg)
	end
end

----- pre-defined widget types -----

-- see tk docs for usage.
-- named parameters do not need the '-' before the name, ltcl.makearglist takes
-- care of that

-- ttk::button widget
_M.button = makewidget('ttk::button', 'button', {
	'invoke', 'identify'
})

-- canvas widget
_M.canvas = makewidget('canvas', nil, {
	'addtag',
	['bbox'] = function(wid, ...)
		local args = mkarglist(...)
		local res = tcl_callt(wid._id, 'bbox', args)
		if type(res) == 'string' then res = tcl_interp:list2table(res) end
		return res
	end,
	'canvasx', 'canvasy',
	['coords'] = function(wid, ...)
		local args = mkarglist(...)
		local res = tcl_callt(wid._id, 'coords', args)
		if type(res) == 'string' then res = tcl_interp:list2table(res) end
		return res
	end,
	['create_arc'] = { 'create', 'arc' },
	['create_bitmap'] = { 'create', 'bitmap' },
	['create_image'] = { 'create', 'image' },
	['create_line'] = { 'create', 'line' },
	['create_oval'] = { 'create', 'oval' },
	['create_polygon'] = { 'create', 'polygon' },
	['create_rectangle'] = { 'create', 'rectangle' },
	['create_text'] = { 'create', 'text' },
	['create_window'] = { 'create', 'window' },
	'dchars', 'delete', 'dtag', 'find', 'focus', 'gettags', 'icursor', 'index',
	'insert',
	['itembind'] = 'bind',
	['itemcget'] = mkitemcgetfunc('itemcget'),
	['itemconfigure'] = mkitemconfigurefunc('itemconfigure'),
	'lower', 'move', 'postscript', 'raise', 'scale',
	['scan_mark'] = { 'scan', 'mark' },
	['scan_dragto'] = { 'scan', 'dragto' },
	['select_adjust'] = { 'select', 'adjust' },
	['select_clear'] = { 'select', 'clear' },
	['select_from'] = { 'select', 'from' },
	['select_item'] = { 'select', 'item' },
	['select_to'] = { 'select', 'to' },
	'type', 'xview',
	['xview_moveto'] = { 'xview', 'moveto' },
	['xview_scroll'] = { 'xview', 'scroll' },
	'yview',
	['yview_moveto'] = { 'yview', 'moveto' },
	['yview_scroll'] = { 'yview', 'scroll' }
})

-- ttk::checkbutton widget
_M.checkbutton = makewidget('ttk::checkbutton', 'checkbutton', {
	'invoke', 'identify'
})

-- ttk::combobox widget
_M.combobox = makewidget('ttk::combobox', 'combobox', {
	'bbox', 'current', 'delete', 'get', 'icursor', 'identify', 'index', 'insert',
	['selection_clear'] = { 'selection', 'clear' },
	['selection_present'] = { 'selection', 'present' },
	['selection_range'] = { 'selection', 'range' },
	'set', 'xview',
	['xview_moveto'] = {'xview', 'moveto'},
	['xview_scroll'] = {'xview', 'scroll'}
})

-- ttk:entry widget
_M.entry = makewidget('ttk::entry', 'entry', {
	'bbox', 'delete', 'get', 'icursor', 'identify', 'index', 'insert',
	['selection_clear'] = { 'selection', 'clear' },
	['selection_present'] = { 'selection', 'present' },
	['selection_range'] = { 'selection', 'range' },
	['set'] = function(wid, t)
		tcl_call(wid._id, 'delete', 0, 'end')
		return tcl_call(wid._id, 'insert', 0, t)
	end,
	'validate', 'xview',
	['xview_moveto'] = {'xview', 'moveto'},
	['xview_scroll'] = {'xview', 'scroll'}
})

-- ttk::frame widget
_M.frame = makewidget('ttk::frame', 'frame', {
	'identify'
})

-- ttk::label widget
_M.label = makewidget('ttk::label', 'label', {
	'identify'
})

-- ttk::labelframe widget
_M.labelframe = makewidget('ttk::labelframe', 'labelframe', {
	'identify'
})

-- listbox widget
_M.listbox = makewidget('listbox', nil, {
	'activate', 'bbox', 'curselection', 'delete', 'get',
	'index', 'insert',
	['itemcget'] = mkitemcgetfunc('itemcget'),
	['itemconfigure'] = mkitemconfigurefunc('itemconfigure'),
	'nearest',
	['scan_mark'] = {'scan', 'mark'},
	['scan_dragto'] = {'scan', 'dragto'},
	'see',
	['selection_anchor'] = { 'selection', 'anchor' },
	['selection_clear'] = { 'selection', 'clear' },
	['selection_includes'] = { 'selection', 'includes' },
	['selection_set'] = { 'selection', 'set' },
	'size', 'xview',
	['xview_moveto'] = {'xview', 'moveto'},
	['xview_scroll'] = {'xview', 'scroll'},
	'yview',
	['yview_moveto'] = {'yview', 'moveto'},
	['yview_scroll'] = {'yview', 'scroll'}
})

-- menu widget
_M.menu = makewidget('menu', nil, {
	'activate', 'add', 'clone', 'delete',
	['entrycget'] = mkitemcgetfunc('entrycget'),
	['entryconfigure'] = mkitemconfigurefunc('entryconfigure'),
	'index',  'insert', 'invoke', 'post', 'postcascade',
	'type', 'unpost', 'xposition', 'yposition'
})

-- ttk::menubutton widget
_M.menubutton = makewidget('ttk::menubutton', nil, {
	'identify'
})

-- message widget
_M.message = makewidget('message', nil, {
})

-- ttk::notebook widget
_M.notebook = makewidget('ttk::notebook', 'notebook', {
	'add', 'forget', 'hide', 'identify', 'index', 'insert', 'select', 'tab', 'tabs'
})

-- ttk::panedwindow widget
_M.panedwindow = makewidget('ttk::panedwindow', 'panedwindow', {
	'add', 'forget', 'identify', 'insert', 'pane', 'panes', 'sashpos'
})

-- ttk::progressbar widget
_M.progressbar = makewidget('ttk::progressbar', 'progressbar', {
	'identify', 'start', 'step', 'stop'
})

-- ttk::radiobutton widget
_M.radiobutton = makewidget('ttk::radiobutton', 'radiobutton', {
	'invoke', 'identify'
})

-- ttk::scale widget
_M.scale = makewidget('ttk::scale', 'scale', {
	'identify', 'set', 'get', 'coords'
})

-- ttk::scrollbar widget
_M.scrollbar = makewidget('ttk::scrollbar', 'scrollbar', {
	'delta', 'fraction', 'get', 'identify', 'set'
})

-- ttk::separator widget
_M.separator = makewidget('ttk::separator', 'separator', {
	'identify'
})

-- ttk::sizegrip widget
_M.sizegrip = makewidget('ttk::sizegrip', 'sizegrip', {
	'identify'
})

-- spinbox widget (ttk::spinbox not supported???)
_M.spinbox = makewidget('spinbox', 'spinbox', {
	'bbox', 'delete', 'get', 'icursor', 'identify', 'index', 'insert', 'invoke',
	['scan_mark'] = {'scan', 'mark'},
	['scan_dragto'] = {'scan', 'dragto'},
	['selection_adjust'] = { 'selection', 'adjust'},
	['selection_clear'] = { 'selection', 'clear'},
	['selection_element'] = { 'selection', 'element'},
	['selection_from'] = { 'selection', 'from'},
	['selection_present'] = { 'selection', 'present'},
	['selection_range'] = { 'selection', 'range'},
	['selection_to'] = { 'selection', 'to'},
	'set', 'validate', 'xview',
	['xview_moveto'] = { 'xview', 'moveto' },
	['xview_scroll'] = { 'xview', 'scroll' }
})

-- text widget
local _text_dump = mkpreoptionsfunc('dump')
_M.text = makewidget('text', nil, {
	'bbox', 'compare',
	['count'] = mkpreoptionsfunc('count'),
	'debug', 'delete', 'dlineinfo',
	['dump'] = function(txt, ...)
		local r0 = _text_dump(txt, ...)
		local r1 = {{}}
		local s, e = s_find(r0, '^[^ ]+ ')
		local i, k = 1, 1
		while s do
			local ns = e + 1
			if s_sub(r0, s, s) == '{' then
				r1[i][k] = s_sub(r0, s + 1, e - 2)
			else
				r1[i][k] = s_sub(r0, s, e - 1)
			end
			if s_sub(r0, ns, ns) == '{' then
				s, e = s_find(r0, '{([^}]+)} ', ns)
			else
				s, e = s_find(r0, '([^ ]+) ', ns)
			end
			k = k + 1
			if k == 4 then
				k = 1
				i = i + 1
				r1[i] = {}
			end
		end
		return r1
	end,
	['edit_modified'] = { 'edit', 'modified' },
	['edit_redo'] = { 'edit', 'redo' },
	['edit_reset'] = { 'edit', 'reset' },
	['edit_separator'] = { 'edit', 'separator' },
	['edit_undo'] = { 'edit', 'undo' },
	'get',
	['get_displaychars'] = function(s, e) return tcl_call(txt._id, 'get', '-displaychars', s, e) end,
	['getcursor'] = function(txt) return tcl_call(txt._id, 'index', 'insert') end,
	['image_cget'] = mkitemcgetfunc('image', 'cget'),
	['image_configure'] = mkitemconfigurefunc('image', 'configure'),
	['image_create'] = { 'image', 'create' },
	['image_names'] = { 'image', 'names' },
	'index', 'insert',
	['mark_names'] = { 'mark', 'names' },
	['mark_next'] = { 'mark', 'next' },
	['mark_previous'] = { 'mark', 'previous' },
	['mark_set'] = { 'mark', 'set' },
	['mark_unset'] = { 'mark', 'unset' },
	['peer_create'] = { 'peer', 'create' },
	['peer_names'] = { 'peer', 'names' },
	'replace',
	['scan_mark'] = { 'scan', 'mark' },
	['scan_dragto'] = { 'scan', 'dragto' },
	['search'] = mkpreoptionsfunc('search'),
	'see',
	['setcursor'] = function(txt, pos) return tcl_call('tk::TextSetCursor', txt._id, pos) end,
	['tag_add'] = { 'tag', 'add' },
	['tag_bind'] = { 'tag', 'bind' },
	['tag_cget'] = mkitemcgetfunc('tag', 'cget'),
	['tag_configure'] = mkitemconfigurefunc('tag', 'configure'),
	['tag_delete'] = { 'tag', 'delete' },
	['tag_lower'] = { 'tag', 'lower' },
	['tag_names'] = { 'tag', 'names' },
	['tag_nextrange'] = { 'tag', 'nextrange' },
	['tag_prevrange'] = { 'tag', 'prevrange' },
	['tag_raise'] = { 'tag', 'raise' },
	['tag_ranges'] = { 'tag', 'ranges' },
	['tag_remove'] = { 'tag', 'remove' },
	['window_cget'] = mkitemcgetfunc('window', 'cget'),
	['window_configure'] = mkitemconfigurefunc('window', 'configure'),
	['window_create'] = { 'window', 'create' },
	['window_names'] = { 'window', 'names' },
	'xview',
	['xview_moveto'] = { 'xview', 'moveto' },
	['xview_scroll'] = { 'xview', 'scroll' },
	'yview',
	['yview_moveto'] = { 'yview', 'moveto' },
	['yview_scroll'] = { 'yview', 'scroll' },
	['yview_number'] = { 'yview', 'number' },
})

-- toplevel
local function _toplevel_mkwmfn(cmd)
	return function(widget, ...)
		local res = tcl_call('wm', cmd, widget._id, ...)
		if s_find(res, ' ') then res = tcl_interp:list2table(res) end
		return res
	end
end
_M.toplevel = makewidget('toplevel', nil, {
	['aspect'] = _toplevel_mkwmfn('aspect'),
	['deiconify'] = _toplevel_mkwmfn('deiconify'),
	['focusmodel'] = _toplevel_mkwmfn('focusmodel'),
	['geometry'] = _toplevel_mkwmfn('geometry'),
	['group'] = _toplevel_mkwmfn('group'),
	['iconbitmap'] = _toplevel_mkwmfn('iconbitmap'),
	['iconify'] = _toplevel_mkwmfn('iconify'),
	['iconmask'] = _toplevel_mkwmfn('iconmask'),
	['iconname'] = _toplevel_mkwmfn('iconname'),
	['iconphoto'] = _toplevel_mkwmfn('iconphoto'),
	['iconposition'] = _toplevel_mkwmfn('iconposition'),
	['iconwindow'] = _toplevel_mkwmfn('iconwindow'),
	['maxsize'] = _toplevel_mkwmfn('maxsize'),
	['minsize'] = _toplevel_mkwmfn('minsize'),
	['resizable'] = _toplevel_mkwmfn('resizable'),
	['stackorder'] = _toplevel_mkwmfn('stackorder'),
	['state'] = _toplevel_mkwmfn('state'),
	['title'] = _toplevel_mkwmfn('title'),
	['transient'] = _toplevel_mkwmfn('transient'),
})

-- ttk::treeview widget
_M.treeview = makewidget('ttk::treeview', 'treeview', {
	'box', 'children', 
	['column'] = mkoptionsfunc('column'),
	'delete', 'detach', 'drag',
	'exists', 'focus',
	['heading'] = mkoptionsfunc('heading'),
	'identify', 'index', 'insert',
	['item'] = mkoptionsfunc('item'),
	'move', 'next', 'parent', 'prev', 'see', 'selection', 'set', 'tag',
	'xview', 'yview'
})

----- utility functions -----

-- require utility function: load a tk package to the tcl interpreter
_M.require = function(pkg)
	local errvar = '_lua_package_require_error'
	local err = tcl_call('catch', {'package', 'require', pkg}, errvar)
	if err ~= 0 then
		error(ltk.var[errvar], 2)
	end
end

-- addtkwidget utility function: add tk widgets from packages loaded with addtkpackage
-- TODO
_M.addtkwidget = makewidget

-- ltcl fromutf8 function
--
_M.fromutf8 = function(str, enc)
	return tcl_interp:fromutf8(str, enc)
end

-- is_widget utility function
-- returns true if the argument is a widget, false otherwise
--
_M.iswidget = function(w)
	return getmetatable(w) == ltk_widget_id
end

-- ltcl toutf8 function
--
_M.toutf8 = function(str, enc)
	return tcl_interp:toutf8(str, enc)
end

-- vals utility function
-- packs its arguments into a ltcl_interp:tuple
--
_M.vals = function(...)
	return tcl_interp:vals(...)
end

-- widget utility function(s)
--  calling ltk.widget as a function returns the widget associated with the
--  widget id passed as argument
--
_M.widget = setmetatable({
	-- widget.id utility function
	-- return id of tk widget or nil, if the argument is not a ltk widget
	--
	['id'] = function(wid)
		return getmetatable(wid) == ltk_widget_id and wid._id
	end,
	
	-- widget.type utility function
	-- return type of tk widget or nil, if the argument is not a ltk widget
	--
	['type'] = function(wid)
		return getmetatable(wid) == ltk_widget_id and wid._type
	end,
}, {
	__call = function(_, wid)
		return widgets[wid]
	end
})

----- tcl and tk functions -----

-- maketkfunc
-- wrap a tk function for use by lua
--
local function maketkfunc(cmd, subfns)
	local _, k, s, v, ret
	if subfns == nil then
		return function(...) return tcl_callt(cmd, mkarglist(...)) end
	end

	ret = {}

	local cfn
	if subfns[0] then
		if type(subfns[0]) == 'function' then
			cfn = subfns[0]
		else
			cfn = function(_, ...) return tcl_callt(cmd, mkarglist(...)) end
		end
	end

	for _, v in ipairs(subfns) do
		ret[v] = function(...) return tcl_callt(cmd, v, mkarglist(...)) end
	end
	
	for k, s in pairs(subfns) do
		if type(k) == 'string' then
			local ts = type(s)
			ret[k] = {}
			
			if ts == 'table' then
				local lcfn
				if s[0] then
					if type(s[0]) == 'function' then
						cfn = s[0]
					else
						cfn = function(_, ...) return tcl_callt(cmd, k, mkarglist(...)) end
					end
				end
				
				for _, v in ipairs(s) do
					ret[k][v] = function(...) return tcl_callt(cmd, k, v, mkarglist(...)) end
				end
				
				setmetatable(ret[k], {
					__call = lcfn,
					__index = function(_, i) error('unknown '..cmd..'.'..k..' command "'..i..'"', 2) end,
					__newindex = function() end
				})
			elseif ts == 'function' then
				ret[k] = s
			else
				error('bad function definition', 2)
			end
		end
	end
	
	setmetatable(ret, {
		__call = cfn,
		__index = function(_, i) error('unknown '..cmd..' command: "'..i..'"', 2) end,
		__newindex = function() end
	})

	return ret
end

-- tcl after function
-- in order to not re-register functions all the time, we cache registerd
-- functions and try to reuse the registration if possible.
--
_M.after = maketkfunc('after', {
	[0] = true,
	'cancel', 'idle', 'info'
})

-- tk bell function
--
_M.bell = function()
	return tcl_call('bell')
end

-- tk bind function 
--
_M.bind = function(widget, events, cmd, plus)
	local wid

	if widget == 'all' then
		widget = all_widgets
	end
	wid = widget._id

	if not wid then error('bad widget "'..tostring(widget)..'"', 2) end
	
	if plus then
		plus = '+ '
	else
		plus = ''
	end

	-- special treatment for Destroy events: as we register such events ourself
	-- additional Destroy events will be handled internally by the ltk Destroy
	-- event handler.
	if events == '<Destroy>' and tcl_call('bind', wid, '<Destroy>') ~= '' then
		if plus ~= '' then
			t_insert(widget._destroyfns, cmd)
		else
			widget._destroyfns = { cmd }
		end
	else
		-- if we have a function to be called with arguments, we create a wrapper
		-- for the event handler that converts widget path names to actual widgets
		-- in the argument list.
		-- Obacht: if a <Destroy> event gets here, it is a low level event and
		-- needs to not have its %W fixed!
		if type(cmd) == 'table' and events ~= '<Destroy>' then
			local f = cmd[1]
			local tofix = {}
			local k, v
			for k, v in ipairs(cmd) do
				if v == '%W' then tofix[#tofix+1] = k - 1 end
			end
			
			-- only create wrapper if there are any %Ws to be fixed
			if #tofix > 0 then
				cmd[1] = function(...)
					local args = {...}
					local _, k
					for _, k in ipairs(tofix) do
						args[k] = widgets[args[k]]
					end
					f(t_unpack(args))
				end
			end
		end

		-- instead of just calling our handler we create a script that will break
		-- the event chain if the event handler returns true (or 1)
		local lcmd
		local toreg, newcmd = registerfunc(cmd)
		if toreg then t_insert(widget._registered, toreg) end
		if type(newcmd) == 'table' then
			lcmd = '[' .. newcmd[1]
			local i, s
			for i=2, #newcmd do
				s = newcmd[i]
				lcmd = lcmd .. ' "' .. s .. '"'
			end
			lcmd = lcmd .. ']'
		else
			lcmd = '[' .. newcmd .. ']'
		end

		local bcmd = 'bind ' .. wid .. ' ' .. events .. plus .. ' { if { ' .. lcmd .. ' == 1 } then { break } }'
		return tcl_interp:eval(bcmd)
	end
end

-- tk bindtags function
_M.bindtags = maketkfunc('bindtags')

-- tk clipboard function
-- clipboard.get, clipboard.append, clipboard.clear
--
_M.clipboard = maketkfunc('clipboard', {
	'get', 'clear',
	['append'] = function(data, opts)
		local opts = mkarglist(opts)
		t_insert(opts, '--')
		t_insert(opts, data)
		t_remove(opts, 1)
		tcl_interp:callt('clipboard', 'append', opts)
	end
})

-- tk console function
-- Obacht: this may not be available on all systems (indeed, it is only
-- available on systems without a proper console...)
--
_M.console = maketkfunc('console', { 'eval', 'hide', 'show', 'title' })

-- tk event function
-- event.set, event.delete, event.generate, event.info
--
_M.event = maketkfunc('event', { 'add', 'delete', 'info',
	['generate'] = function(wid, event, options)
		local args = mkarglist(options)
		return tcl_interp:callt('event', 'generate', wid._id, event, args)
	end
})

-- tcl/tk exit function
-- exit the tcl/Tk interpreter, and thus the application.
--
_M.exit = function(code)
	code = code or 0
	tcl_call('destroy', '.')
	os_exit(code)
end

-- tk focus function
--
_M.focus = function(wid, options)
	if type(options) == 'table' then
		local opts = fix_switches(options)
		opts[#opts] = wid._id
		return tcl_callt('focus', opts)
	elseif options then
		return tcl_call('focus', '-'..options, wid._id)
	else
		return tcl_call('focus')
	end
end

-- tk font function
--
_M.font = maketkfunc('font', {
	['actual'] = function(font, a2, a3)
		local option = nil
		local ch = nil
		local r0
		if a3 ~= nil and a2 == nil then
			a2 = a3
			a3 = nil
		end

		if a2 ~= nil and a3 == nil then
			if #a2 == 1 then
				r0 = tcl_call('font', 'actual', font, '--', a2)
			else
				r0 = tcl_call('font', 'actual', font, '-'..a2)
			end
		elseif a2 ~= nil then
			r0 = tcl_call('font', 'actual', font, '-'..a2, a3)
		else
			r0 = fix_optvallist(tcl_call('font', 'actual', font))
		end
		
		return r0
	end,
	['configure'] = function(...)
		local arg
		local a1 = select(1, ...)
		local res

		if select('#', ...) == 1 and type(a1) == 'table' then
			arg = a1
		else
			arg = {...}
		end

		if #arg > 2 then
			return tcl_callt('font', 'configure', arg)
		elseif #arg==2 then
			return tcl_callt('font', 'configure', a1, '-' .. arg[2])
		else
			local r0 = tcl_callt('font', 'configure', a1)
			return fix_optvallist(r0)
		end
	end,
	'create', 'delete',
	'families', 'measure', 'metrics', 'names'
})

-- tk grab function
--
_M.grab = maketkfunc('grab', { 'current', 'release', 'set', 'status' })

-- tk grid function
--
_M.grid = maketkfunc('grid', { [0] = true,
	'anchor', 'bbox', 'columnconfigure', 'configure', 'forget',
	['info'] = function(wid)
		local i = tcl_call('grid', 'info', wid._id)
		if type(i) == 'string' then i = tcl_interp:list2table(i) end
		return fix_optvallist(i)
	end,
	'location', 'propagate', 'rowconfigure', 'remove', 'size', 'slaves'
})

-- tk image function
--
local image_methods = {
	['delete'] = function(img)
		return tcl_call('image', 'delete', img._id)
	end,
	['height'] = function(img)
		return tcl_call('image', 'height', img._id)
	end,
	['inuse'] = function(img)
		return tcl_call('image', 'inuse', img._id)
	end,
	['type'] = function(img)
		return tcl_call('image', 'type', img._id)
	end,
	['width'] = function(img)
		return tcl_call('image', 'width', img._id)
	end
}
widget_command_cache['bitmap'] = mkset {
	['getdata'] = function(img)
		if img.data ~= '' then
			return img.data
		elseif img.file ~= '' then
			local f = io.open(img.file, 'r')
			if f then
				local d = f:read('*a')
				f:close()
				return d
			end
			return nil
		end
		return nil
	end
}		
widget_command_cache['photo'] = mkset {
	'blank', 'copy',
	['getdata'] = 'data',
	['get'] = function(img, x, y)
		local r = tcl_interp:call(img._id, 'get', x, y)
		if type(r) == 'string' then r = tcl_interp:list2table(r) end
		return r
	end,
	'put', 'read', 'redither',
	['transparency_get'] = {'transparency', 'get'},
	['transparency_set'] = {'transparency', 'set'},
	'write',
	-- a friendlier version of "put col -to x,y"
	['set'] = function(img, x, y, col)
		tcl_call(img._id, 'put', col, '-to', tcl_interp:vals(x, y))
	end
}
do local k, v
	for k, v in pairs(image_methods) do
		widget_command_cache['bitmap'][k] = v
		widget_command_cache['photo'][k] = v
	end
end

_M.image = maketkfunc('image', {
	'names', 'types',

	['create_bitmap'] = function(...)
		local opts = mkarglist(...)
		local img = tcl_callt('image', 'create', 'bitmap', opts)
		local wid, widget = create_widget('bitmap', nil, nil, img)
		cache_widget_options(wid, 'bitmap')
		return widget
	end,
	['create_photo'] = function(...)
		local opts = mkarglist(...)
		local img = tcl_callt('image', 'create', 'photo', opts)
		local wid, widget = create_widget('photo', nil, nil, img)
		cache_widget_options(wid, 'photo')
		return widget
	end,
	'create',
	['delete'] = function(...)
		local opts = mkarglist(...)
		local img, no
		for no=1,#opts do
			img = opts[no]
			widgets[img] = nil
		end
		return tcl_callt('image', cmd, opts)
	end
})
_M.image.create = _M.image.create_photo

-- tk lower function
--
_M.lower = function(wid, other)
	return tcl_call('lower', wid._id, other)
end

-- tk raise function
--
_M.raise = function(wid, other)
	return tcl_call('raise', wid._id, other)
end

-- mainloop function
-- add a destroy event handler to the default toplevel window then enter event
-- handler.
--
_M.mainloop = function()
	tcl_call('vwait', 'forever')
end

-- tk option function
--
_M.option = maketkfunc('option', { 'add', 'clear', 'get', 'readfile' })

-- tk pack function
--
_M.pack = maketkfunc('pack', {[0] = true,
	'configure', 'forget',
		['info'] = function(wid)
		local i = tcl_call('pack', 'info', wid._id)
		if type(i) == 'string' then i = tcl_interp:list2table(i) end
		return fix_optvallist(i)
	end,
	'propagate', 'slaves'
})

-- tk place function
--
_M.place = maketkfunc('place', {[0] = true,
	'configure', 'forget',
		['info'] = function(wid)
		local i = tcl_call('place', 'info', wid._id)
		if type(i) == 'string' then i = tcl_interp:list2table(i) end
		return fix_optvallist(i)
	end,
	'slaves'
})

-- tk selection function
--
_M.selection = maketkfunc('selection', {
	'clear', 'get',
	['handle'] = function(...)
		local opts = mkarglist(...)
		if s_sub(opts[1], 1, 1) ~= '-' then t_insert(opts, opts[1]) t_remove(opts, 1) end
		if s_sub(opts[1], 1, 1) ~= '-' then t_insert(opts, opts[1]) t_remove(opts, 1) end
		tcl_callt('selection', 'handle', opts)
	end,
	['own'] = function(...)
		local opts = mkarglist(...)
		if s_sub(opts[1], 1, 1) ~= '-' then t_insert(opts, opts[1]) t_remove(opts, 1) end
		tcl_callt('selection', 'handle', opts)
	end
})

-- tk tk function
--
_M.tk = maketkfunc('tk', {'appname', 'scaling', 'inactive', 'useinputmethods', 'windowingsystem',
	['caret'] = { 'window' }
})

-- tk tk_chooseColor function
--
_M.chooseColor = maketkfunc('tk_chooseColor')

-- tk tk_chooseDirectory function
--
_M.chooseDirectory = maketkfunc('tk_chooseDirectory')

-- tk tk_dialog function
-- Note: generates its own id, and disposes of it after use
--
_M.dialog = function(...)
	local opts = mkarglist(...)
	local id = genid()
	local res = tcl_callt('tk_dialog', id, opts)
	tcl_call('destroy', id)
	return res
end

-- tk tk_focusFollowsMouse function
--
_M.focusFollowsMouse = function()
	return tcl_call('tk_focusFollowsMouse')
end

-- tk tk_focusNext function
--
_M.focusNext = function(wid)
	return tcl_call('tk_focusNext', wid._id)
end

-- tk tk_focusPrev funcion
--
_M.focusPrev = function(wid)
	return tcl_call('tk_focusPrev', wid.w_id)
end

-- tk tk_getOpenFile function
--
_M.getOpenFile= maketkfunc('tk_getOpenFile')

-- tk tk_getSaveFile function
--
_M.getSaveFile = maketkfunc('tk_getSaveFile')

-- tk tk_menuSetFocus function
--
_M.menuSetFocus = maketkfunc('tk_menuSetFocus')

-- tk tk_messageBox function
--
_M.messageBox = maketkfunc('tk_messageBox')

-- tk tk_optionMenu function
-- we create a pseudowidget wrapping the menu returned by tk_optionMenu so that
-- a widget command for it can be created to manipulate the widget. The widget
-- created for the optionmenu button is also returned, so that it can be used
-- with layout managers.
--
-- In a deviation from the Tk tk_optionMenu function, the first arg here may
-- also be a function.
--
_M.optionMenu = function(...)
	local a1 = select(1, ...)
	local var_or_func = (type(a1) == 'table') and a1[1] or a1
	local opts = mkarglist(...)
	local id = genid()
	local wid, button = create_widget('optionMenu', nil, nil, id)
	local tmpvar
	if type(var_or_func) == "function" then
		tmpvar = genvar() --genid()
		opts[1] = tmpvar
	end
	local rmid = tcl_callt('tk_optionMenu', id, opts)
	local mid, menu = create_widget('menu', nil, nil, rmid)
	cache_widget_options(wid, 'optionMenu')
	cache_widget_options(rmid, 'menu')
	if tmpvar then
		local cbfunc = function(name1, name2, flags)
			return var_or_func(id, _M.var[name1])
		end
		rawset(button, '_callback',  cbfunc)
		tcl_interp:tracevar(tmpvar, nil, tcl_interp.TRACE_WRITES, cbfunc)
	end
	return button, menu
end

-- tk tk_popup function
--
_M.popup = maketkfunc('tk_popup')

-- tk tk_setPalette function
--
_M.setPalette = maketkfunc('tk_setPalette')

-- tk tkwait function
--
_M.wait = maketkfunc('tkwait', { 'variable', 'visibility', 'window' })

-- tcl update function
--
_M.update = maketkfunc('update', { [0] = true, 'idletasks' })

-- tk winfo function
--
_M.winfo = maketkfunc('winfo', {
	'atom', 'atomname', 'cells', 'children', 'class', 'colormapfull', 'containing',
	'depth', 'exists', 'fpixels', 'geometry', 'height', 'id', 'interps', 'ismapped',
	'manager', 'name', 'parent', 'pathname', 'pixels', 'pointerx', 'pointerxy',
	'pointery', 'reqheight', 'reqwidth', 'rgb', 'rootx', 'rooty', 'screen',
	'screencells', 'screendepth', 'screenheight', 'screenmmheight', 'screenmmwidth',
	'screenvisual', 'screenwidth', 'server', 'toplevel', 'visual', 'viewable',
	'visualid', 'visualsavailable', 'vrootheight', 'vrootwidth', 'vrootx',
	'vrooty', 'width', 'x', 'y'
})

-- tk wm function
--
_M.wm = maketkfunc('wm', {
	'aspect', 'attributes', 'client', 'colormapwindows', 'command', 'deiconify',
	'focusmodel', 'forget', 'frame', 'geometry', 'grid', 'group', 'iconbitmap',
	'iconify', 'iconmask', 'iconname', 'iconphoto', 'iconposition', 'iconwindow',
	'manage', 'maxsize', 'minsize', 'overrideredirect', 'positionfrom', 'protocol',
	'resizable', 'sizefrom', 'stackorder', 'state', 'title', 'transient', 'withdraw'
})

----- ttk functions -----

-- ttk::style function --TODO style.configure und alles Andere
--
_M.style = maketkfunc('ttk::style', {
	['configure'] = function(a1, a2)
		if a2 ~= nil then
			return tcl_call('ttk::style', 'configure', a1, '-'..a2)
		elseif type(a1) == 'table' then
			return tcl_callt('ttk::style', 'configure', mkarglist(a1))
		else
			local res = tcl_callt('ttk::style', 'configure', a1)
			return fix_optvallist(res)
		end
	end,
	['map'] = function(style, option, ...)
		local spec = {...}
		if #spec == 1 and type(spec[1]) == 'table' then spec = spec[1] end
		return tcl_call('ttk::style', 'map', style, '-'..option, spec)
	end,
	['lookup'] = function(style, option, state, default)
		return tcl_callt('ttk::style', {'lookup', style, '-'..option, state, default})
	end,
	'layout',
	['theme'] = {'create', 'settings', 'names', 'use'},
	['element'] = {'create', 'names', 'options'}
})
_M.style.element.options = function(elem)
	local res = tcl_call('ttk::style', 'element', 'options', elem)
	local i
	for i=1, #elem do
		res[i] = res[i] and s_sub(res[i], 2)
	end
	return res
end

----- final setup -----

-- register default toplevel widget
_, _M.stdwin = create_widget('toplevel', 'toplevel', nil, '.')
cache_widget_options('.', 'toplevel')

-- prepare main '.' window so that closing it will do the right thing.
_M.bind(widgets['.'], '<Destroy>', {
	function(wid)
		if wid=='.' then
			tcl_call('bind', '.', '<Destroy>', '')
			destroywidget('.', '??', '??', '??', '.')
			_M.exit()
		end
	end, '%W'})

-- additional setup to make ltk more friendly

-- remove tearoff functionality from menus. Can be re-enabled if needed, but
-- this removes the dreaded tearoff line at the start of a menu
_M.option.add('*tearOff', 0)

-- return exported definitions
return _M
