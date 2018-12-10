--  2018 AoC 10 -- sprite writing

local ltk = require "ltk"

infile = io.open("2018_advent_10a.txt")
input = infile:read("a")
infile:close()

points = {}

for x, y, dx, dy in string.gmatch(input, "position=<%s*(%-?%d+),%s*(%-?%d+)> velocity=<%s*(%-?%d+),%s*(%-?%d+)>") do
    points[#points+1] = {x = tonumber(x), y = tonumber(y), dx = tonumber(dx), dy = tonumber(dy)}
end

print ("Read ", #points, " points")

local limit = 256  

-- the canvas on which we draw
c = ltk.canvas {width = limit, height = limit} 
c:pack()

for i = 1, #points do
    points[i].sprite = c:create_rectangle {i * 2 - 1,
                                           i * 2 - 1,
                                           i * 2 + 1, 
                                           i * 2 + 1,
                                           fill='black', 
                                           tags={''}}
end

local steps = 0

while true do
    local maxx = 0
    local maxy = 0
    local minx = 1000000
    local miny = 1000000
    for i = 1, #points do
        local p = points[i]
        p.x = p.x + p.dx
        p.y = p.y + p.dy
        if p.x < minx then minx = p.x end
        if p.y < miny then miny = p.y end
        if p.x > maxx then maxx = p.x end
        if p.y > maxy then maxy = p.y end
    end
    steps = steps + 1

    if (maxx - minx) < limit and (maxy - miny) < limit then
        for i = 1, #points do
            local p = points[i]
            p.x = p.x - minx
            p.y = p.y - miny
            c:coords(p.sprite, p.x - 1, p.y - 1, p.x + 1, p.y + 1)
        end
        break
    end
end

local pause = false

function drawimg()
    if not pause then
        for i = 1, #points do
            local p = points[i]
            c:move(p.sprite, p.dx, p.dy)
            p.x = p.x + p.dx
            p.y = p.y + p.dy
        end
        steps = steps + 1
    else
        if lastp ~= steps then
            print ("Paused at ", steps)
            lastp = steps
        end
    end
    ltk.after{500, drawimg}
end

b = ltk.button {text="Pause", command=function() pause = not pause end}

c:grid{row=1}
b:grid{row=2}

-- show window and all
ltk.update()

-- initial image
drawimg()

-- and run
ltk.mainloop()

-- print("Part 1: ", tick) -- GEJKHGHZ
-- print("Part 2: ", steps) -- 10681

print ("Done")
