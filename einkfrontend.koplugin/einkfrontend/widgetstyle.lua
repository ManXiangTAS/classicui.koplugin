-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- A reversible presentation policy for standard KOReader controls. Paint-time
-- overrides also cover existing widgets, reinit, and Button's feedback frames.
-- Never change Size.radius globally: button highlight/undo uses it as state.
local Frame = require("ui/widget/container/framecontainer")
local Progress = require("ui/widget/progresswidget")
local Style = { owners = setmetatable({}, { __mode = "k" }), records = {} }

local function pack(...) return { n = select("#", ...), ... } end

local function isCircle(widget)
    local size = widget:getSize()
    local w, h = widget.width or size.w, widget.height or size.h
    return w > 0 and h > 0 and math.abs(w - h) <= 1
        and widget.radius >= math.min(w, h) / 2 - 1
end

local function wrap(class, preserve_circles)
    local original = class.paintTo
    local record = { class = class, raw = rawget(class, "paintTo") }
    record.wrapper = function(widget, ...)
        if not next(Style.owners) or widget._eink_keep_shape
            or type(widget.radius) ~= "number" or widget.radius <= 0
            or (preserve_circles and not widget._eink_force_square and isCircle(widget)) then
            return original(widget, ...)
        end
        -- Preserve raw/inherited values, even when a child painter throws.
        -- In particular, leave Button's highlight/undo state unchanged.
        local radius = rawget(widget, "radius")
        widget.radius = 0
        local result = pack(pcall(original, widget, ...))
        widget.radius = radius
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    class.paintTo = record.wrapper
    Style.records[#Style.records + 1] = record
end

function Style.install(owner)
    assert(owner, "widget style requires an owner")
    Style.owners[owner] = true
    if #Style.records > 0 then return end
    wrap(Frame, true)
    wrap(Progress, false)
end

function Style.detach(owner)
    Style.owners[owner] = nil
    if next(Style.owners) then return end
    for i = #Style.records, 1, -1 do
        local record = Style.records[i]
        -- A later third-party wrapper must not be overwritten. If it retained
        -- our wrapper, that wrapper is inert until another owner is installed.
        if record.class.paintTo == record.wrapper then
            record.class.paintTo = record.raw
        end
    end
    Style.records = {}
end

return Style
