-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Two-row anchored menu for the settings root; never replaces the current page.
local Input = require('ui/widget/container/inputcontainer')
local Device = require('device')
local UI = require('ui/uimanager')
local GestureRange = require('ui/gesturerange')
local P = require('einkfrontend/paint')
local S = P.s
local Popup = Input:extend{stop_events_propagation=true, modal=true}

function Popup:init()
    self.dimen = Device.screen:getSize()
    self.rows = {
        {text='搜索', callback=function()
            self:close()
            self.app:searchSettings()
        end},
        {text='重启 KOReader', callback=function()
            self:close()
            self.app:confirm('保存设置并重启 KOReader？', function()
                UI:flushSettings()
                UI:restartKOReader()
            end)
        end},
    }
    self.ges_events = {}
    for name, ges in pairs({SettingsPopupTap='tap', SettingsPopupSwipe='swipe',
        SettingsPopupHold='hold', SettingsPopupPan='pan', SettingsPopupPanRelease='pan_release'}) do
        self.ges_events[name] = {GestureRange:new{ges=ges, range=self.dimen}}
    end
end

function Popup:close() UI:close(self, 'ui') end
function Popup:onCloseWidget()
    if self.app.settings_popup == self then self.app.settings_popup = nil end
    if self.app.screen then UI:setDirty(self.app.screen, 'ui') end
end

function Popup:paintTo(bb, x, y)
    self.hits = {}
    local page = self.app.screen
    local anchor = page and page.settings_more_anchor
    local w, rh = math.min(S(238), self.dimen.w-S(24)), S(52)
    local right = anchor and anchor.x+anchor.w or x+self.dimen.w-S(53)
    local top = anchor and anchor.y+anchor.h or y+(page and page.header_h or S(58))
    local px = math.max(x+S(12), math.min(right-w, x+self.dimen.w-w-S(12)))
    local py = math.max(y, math.min(top, y+self.dimen.h-2*rh))
    self.box = {x=px, y=py, w=w, h=2*rh}
    bb:paintRect(px, py, w, 2*rh, P.BB.COLOR_WHITE)
    bb:paintBorder(px, py, w, 2*rh, math.max(2, S(1.5)), P.BB.COLOR_BLACK)
    for i, row in ipairs(self.rows) do
        local ry = py+(i-1)*rh
        P.inkLabel(bb, row.text, px+S(16), ry, w-S(32), rh, P.style.label, true, nil, 'left')
        self.hits[#self.hits+1] = {x=px, y=ry, w=w, h=rh, callback=row.callback,
            id=i==1 and 'settings_popup_search' or 'settings_popup_restart'}
        if i==1 then P.line(bb, px+S(12), ry+rh, w-S(24)) end
    end
end

function Popup:onSettingsPopupTap(_, ges)
    if not P.activate(self, ges and ges.pos) then self:close() end
    return true
end
function Popup:onSettingsPopupSwipe() self:close(); return true end
function Popup:onSettingsPopupHold() return true end
function Popup:onSettingsPopupPan() return true end
function Popup:onSettingsPopupPanRelease() return true end
function Popup:onKeyPress(key)
    if key:match({Device.input.group.Back}) then self:close() end
    return true
end
Popup.onKeyRepeat = Popup.onKeyPress
function Popup:onSetDimensions() self:close(); return false end
function Popup:onSuspend() self:close() end

return Popup
