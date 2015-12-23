#!/usr/bin/env lua

--[[
 - ltkhtext.lua
 -
 - a simple hypertext browser, illustrates tagging parts of text, styling them
 - and reacting on them
 -
 - Gunnar Zötl <gz@tset.de>, 2011.
 - Released under MIT/X11 license. See file LICENSE for details.
 -
 - 2011-10-17 adjusted for ltk version 2
 --]]

ltk = require "ltk"

-- everything between [brackets] is a link, using what's betwen the brackets
-- as an index into this array.
texts = {
	intro = [[This is a sample text. It contains [links] to other texts. Otherwise it is filled with [nonsense] like this:
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Etiam quis semper lacus. Curabitur tempor augue ut erat sollicitudin placerat pharetra lacus condimentum. Vestibulum arcu neque, vestibulum sit amet iaculis sed, placerat at metus. Ut vitae elit felis, ac iaculis elit. Maecenas vel leo mi. Etiam urna felis, accumsan ut semper in, laoreet ac sapien. In hac habitasse platea dictumst. Vivamus rutrum sapien in velit rutrum ultrices vulputate arcu suscipit. Vivamus tristique facilisis augue, vitae convallis nulla fringilla vitae. Cras at ipsum tellus, vel tempor orci. Nam dictum mi non elit egestas sed posuere neque gravida.]],
	links = [[This is some text about links. From here you can go back to the [intro] or read some more [nonsense] like this:
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc adipiscing, massa id convallis luctus, libero eros rutrum erat, et laoreet augue ante vitae sapien. Nam quis ipsum eu nisi pharetra venenatis vitae ut nisl. Nulla id viverra magna. Aliquam ut ipsum vitae justo adipiscing dictum nec a urna. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nam sagittis commodo dapibus. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent sed leo odio, ut sollicitudin enim. Fusce ac lectus diam. Etiam interdum lobortis ante, at lobortis eros auctor id. Curabitur pulvinar arcu eget sem bibendum semper.]],
	nonsense = [[This is just a bunch of nonsense. To spice it up some, it contains [links], such as the one to the [intro] page. Also, there's nonsense:
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam neque nisi, tempus eu placerat ut, tincidunt sit amet tellus. Maecenas lobortis, nibh quis imperdiet luctus, neque augue condimentum justo, et ultrices mi odio id nibh. Ut dui nunc, pretium ac iaculis at, accumsan et magna. Vestibulum non nulla ut lacus luctus tristique sed sed quam. Nulla id diam quam, id aliquam nisl. Phasellus vitae tempus mauris. Sed sagittis metus et justo malesuada placerat. Sed eget urna mi, eu dignissim nulla. Mauris tincidunt lobortis dui, in suscipit sem dictum at. Cras nunc est, tempor a fermentum eu, vehicula varius risus. Donec sit amet nisl velit, ultrices vulputate libero.]],
}

txt = ltk.text {width=60, height=40, wrap = 'word'}
txt:pack()

-- empty text widget
function init()
	txt:delete('0.0', 'end')
end

-- render hypertext. Everything between [brackets] is tagged with the tag 'link'
function render(which)
	local text = texts[which]
	if text == nil then error("Unknown text.") end

	txt:state('!disabled')

	init()
	
	local ti, fi, oi = 1, 1, 1
	local pos = '0.0'
	ti, fi = string.find(text, '%[[^%[%]]+%]', oi)
	while ti do
		-- non link
		txt:insert(pos, string.sub(text, oi, ti-1))
		pos = txt:index('insert')
		-- link
		txt:insert(pos, string.sub(text, ti, fi), {'link'})
		pos = txt:index('insert')
		oi = fi + 1
		ti, fi = string.find(text, '%[[^%[%]]+%]', oi)
	end
	-- remaining text
	txt:insert(pos, string.sub(text, oi))
	
	txt:state('disabled')
end

-- from lua users wiki, modified
function explode(s, sep)
        local fields = {}
        local pattern = string.format("([^%s]+)", sep)
        s:gsub(pattern, function(c) fields[#fields+1] = c end)
        return unpack(fields)
end

-- click handler: get link text and render new text
function click(x, y)
	local idx = txt:index('@'..x..','..y)
	local range = txt:tag_prevrange('link', idx)
	local link = txt:get(explode(range, ' '))
	link = string.gsub(link, '^%[(.+)%]$', '%1')
	render(link)
end

txt:tag_configure{'link', background = 'lightblue'}
txt:tag_bind('link', '<Enter>', function() txt:configure{cursor='hand2'} end)
txt:tag_bind('link', '<Leave>', function() txt:configure{cursor=''} end)
txt:tag_bind('link', '<1>', { click, '%x', '%y' })

render('intro')

ltk.mainloop()
