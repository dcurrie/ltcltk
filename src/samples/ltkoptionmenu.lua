#!/usr/bin/env lua

--[[
 - ltkoptionmenu.lua
 -
 - an example for optionmenus - ltk style.
 -
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
 -
 - 2011-10-17 adjusted for ltk version 2
--]]

ltk = require "ltk"

function handle(om, val)
	print("optionMenu '"..tostring(om).."' was set to '"..tostring(val).."'")
end

-- optionmenu with a function
om1, m1 = ltk.optionMenu(handle, 'Func Option 1', 'Func Option 2', 'Func Option 3')
print("optionMenu '"..tostring(om1).."' was created, menu widget is '"..tostring(m1).."'")

-- optionmenu writing selection to tcl variable
ov = ltk.var()
om2, m2 = ltk.optionMenu(ov, 'Var Option 1', 'Var Option 2', 'Var Option 3')
print("optionMenu '"..tostring(om2).."' was created, menu widget is '"..tostring(m2).."'")

var = ""
function checkvar()
	if ltk.var[ov] ~= var then
		var = ltk.var[ov]
		print("optionMenu '"..tostring(om2).."' was set to '"..tostring(var).."'")
	end
	ltk.after(100, checkvar)
end
-- every now and then check wether the variable for the 2nd option menu has changed,
-- for reporting purposes
ltk.after(100, checkvar)

om1:grid()
om2:grid()

ltk.mainloop()
