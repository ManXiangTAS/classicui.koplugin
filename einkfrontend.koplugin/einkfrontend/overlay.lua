-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Own one transient frontend panel across all live reader/file-manager instances.
local UI=require("ui/uimanager")
local Context=require("einkfrontend/context")
local Overlay={}
function Overlay.close(app,except)
 local close={}
 for _,window in ipairs(UI._window_stack) do
  local widget=window.widget
  if widget._eink_overlay and widget~=except and (not app or widget.app==app) then close[#close+1]=widget end
 end
 for _,widget in ipairs(close) do widget:close() end
end
function Overlay.present(app,key,create)
 if not Context.allowed(app,key) then return end
 if app._opening_overlay then return app[key] end
 app:closeDialogs()
 app._opening_overlay=true
 local ok,result=pcall(function()
  local current
  for _,window in ipairs(UI._window_stack) do
   local widget=window.widget
   if widget._eink_overlay==key and widget.app==app then current=widget;break end
  end
  Overlay.close(nil,current)
  if current then app[key]=current;return current end
  local widget=create();widget._eink_overlay=key
  if key=='settings_popup' or key=='library_popup' then widget._eink_route=app.stack[#app.stack] end
  app[key]=widget
  UI:show(widget,"ui");return widget
 end)
 app._opening_overlay=nil
 if not ok then error(result) end
 return result
end
function Overlay.closeInvalid(app)
 local close={}
 for _,window in ipairs(UI._window_stack) do
  local widget=window.widget
  if widget.app==app and widget._eink_overlay and not Context.allowed(app,widget._eink_overlay,widget) then close[#close+1]=widget end
 end
 for _,widget in ipairs(close) do widget:close() end
end
return Overlay
