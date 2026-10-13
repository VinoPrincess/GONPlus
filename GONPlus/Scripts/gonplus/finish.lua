-- читы лаборатории
every(100, function()
    if not (LAB.god or LAB.invis) then return end
    local p = getPawn(); if not p then return end
    if LAB.god then pcall(function() if (num(p.health) or 1) < 1 then p.health = 1.0 end end) end
    if LAB.invis then pcall(function() if p.IsMaskOn ~= true then p.IsMaskOn = true end end) end
end)

-- влево/вправо по числовым строкам лаборатории (вызывается из общих обработчиков стрелок)
labNumChange = function(dir)
    local it = UI.items[UI.sel]
    if it and it.labNum then
        LAB[it.labNum] = math.max(it.min, math.min(it.max, LAB[it.labNum] + dir * it.step))
    end
end

math.randomseed(os.time())
log("Loaded! v" .. VERSION .. " by " .. AUTHOR .. " (" .. #MUT_ORDER .. " mutators, scheduler: " .. SCHED_MODE .. ")")
