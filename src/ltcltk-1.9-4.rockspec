package = "ltcltk"
version = "1.9-4"
source = {
	url = "http://www.tset.de/downloads/ltcltk-1.9-4.tar.gz"
}
description = {
	summary = "A binding for lua to the tcl interpreter and to the tk toolkit.",
	detailed = [[
		This is a binding of the tcl interpreter to lua. It allows
		for calls into tcl, setting and reading variables from tcl and
		registering of lua functions for use from tcl.
		Also, a binding to the tk toolit is included.
	]],
	homepage = "http://www.tset.de/ltcltk/",
	license = "MIT/X11",
	maintainer = "Gunnar Zötl <gz@tset.de>"
}
supported_platforms = {
	"unix", "mac"
}
dependencies = {
	"lua >= 5.1"
}
-- does not work because at least on ubuntu tcl.h is in /usr/include/tk, whereas
-- everywhere else it seems to be in /usr/include. I found no way to deal with this
-- in a civil manner, so I resort to a hack. Part 2 at the end of the file.
-- Bad thing is, I lose luarocks' dependency check :(
--external_dependencies = {
--	TCL = {
--		header = "tcl.h"
--	}
--}
build = {
	type = "builtin",
	modules = {
		ltk = "ltk.lua",
		ltcl = {
			sources = { "ltcl.c" },
			-- needs tcl 8.5!
			libraries = { "tcl8.5" }
		},
	},
	install = {
		bin = { 'ltksh' }
	},
	copy_directories = { 'doc', 'samples' },
	-- this is part 2 of the abovementioned hack. Not pretty, but at least it works. kinda.
	platforms={unix={modules={ltcl={incdirs = { "/usr/include/tk" }}}}} 
}

