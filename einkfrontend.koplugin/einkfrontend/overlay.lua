-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Own one transient frontend panel across all live reader/file-manager instances.
local UI=require("ui/uimanager")
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
 if app._opening_overlay then return app[key] end
 app._opening_overlay=true
 local ok,result=pcall(function()
  local current
  for _,window in ipairs(UI._window_stack) do
   local widget=window.widget
   if widget._eink_overlay==key and widget.app==app then current=widget;break end
  end
  Overlay.close(nil,current)
  if current then app[key]=current;return current end
  local widget=create();widget._eink_overlay=key;app[key]=widget
  UI:show(widget,"ui");return widget
 end)
 app._opening_overlay=nil
 if not ok then error(result) end
 return result
end
return Overlay
