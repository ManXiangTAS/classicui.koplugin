-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- A real TouchMenu receiver for callbacks; only its presentation is replaced.
local Native={};Native.__index=Native
local categories={
 {"reading","阅读偏好","appbar.book"},{"display","显示与刷新","appbar.light"},
 {"input","触控与按键","appbar.tap"},{"library","书库与文件","appbar.folder"},
 {"lookup","词典与文本工具","appbar.search"},{"network","网络与同步","appbar.wifi"},
 {"plugins","插件与扩展","appbar.puzzle"},{"device","设备与系统","appbar.settings"},
 {"misc","杂项","appbar.more"},{"maintenance","维护与恢复","appbar.settings"},
}
local mapping={navi="reading",typeset="typography",setting="device",tools="plugins",search="lookup",filemanager="library",main="maintenance",
 navi_settings="reading",document="reading",document_end_action="reading",frontlight="display",night_mode="display",screen="display",status_bar="display",
 taps_and_gestures="input",navigation="input",physical_buttons_setup="input",network="network",cloud_storage="network",progress_sync="network",
 dictionary="lookup",wikipedia="lookup",highlight_options="lookup",language="device",device="device",screensaver="device",time="device",
 more_tools="plugins",plugin_management="plugins",plugins="plugins",einkfrontend="compatibility",filemanager_settings="compatibility",filemanager_display_mode="compatibility",filebrowser_settings="compatibility",
 show_filter="compatibility",sort_by="compatibility",reverse_sorting="compatibility",sort_mixed="compatibility",start_with="compatibility",
 help="diagnostics",advanced_settings="diagnostics",developer_options="diagnostics",httpremote="diagnostics",terminal="diagnostics",
 exit_menu="power",history="library",open_last_document="library",open_previous_document="library",favorites="library",collections="library",bookmark_browser="reading",book_status="reading",book_info="reading"}
function Native.new(app)
 local valid={typography=true,compatibility=true,diagnostics=true,power=true};for _,c in ipairs(categories) do valid[c[1]]=true end
 return setmetatable({app=app,categories=categories,catalog=require("einkfrontend/catalog").new(app.plugin.ui,mapping,valid)},Native)
end
Native.extra_categories={{"compatibility","原生界面设置"},{"diagnostics","诊断与高级工具"},{"power","退出与设备操作"}}
function Native:refresh() return self.catalog:refresh() end
function Native.text(node)
 local names={navi="阅读导航",typeset="高级排版",setting="系统设置",tools="工具与插件",search="搜索与查找",filemanager="文件管理",main="更多操作"}
 local ok,result=pcall(function() return node.text_func and node.text_func() or node.text or names[node.id] end)
 return ok and tostring(result or "设置") or "设置（名称暂不可用）"
end
function Native.enabled(node)
 if node.enabled==false then return false end
 if type(node.enabled_func)=="function" then local ok,value=pcall(node.enabled_func);return ok and value~=false end
 return true
end
function Native.checked(node)
 if node.checked_func then local ok,v=pcall(node.checked_func);return ok and v end
 return node.checked
end
function Native:retire()
 if self.host then
  self.host=nil
  local menu=self.app.plugin.ui.menu
  local key=self.app.plugin.ui.document and "onCloseReaderMenu" or "onCloseFileManagerMenu"
  menu[key](menu)
 end
end
function Native:open(nodes,title)
 self:retire()
 local plugin=self.app.plugin
 local function create()
  local menu=plugin.ui.menu
  local method=plugin.gate and plugin.gate:original(menu,"onShowMenu") or menu.onShowMenu
  method(menu,1,true)
  return assert(menu.menu_container[1])
 end
 local host=plugin.gate and plugin.gate:native(create) or create()
 assert(type(host.onMenuSelect)=="function","当前设备菜单宿主不支持触控协议，请使用原生兼容菜单")
 self.host=host;self.titles={title};self.scrolls={0};host.item_table_stack={};host.item_table=nodes
 local update=host.updateItems
 host.updateItems=function(this,...)
  local result=update(this,...)
  if self.host==this and self.app.screen and self.app.stack[#self.app.stack].id=="native" then self.app:render() end
  return result
 end
 host.close_callback=function()
  if self.host==host then self:retire();self.app:dismiss() end
 end
 host:updateItems(1)
 self.app:go("native")
end
function Native:select(node,hold,checkmark)
 if not Native.enabled(node) then return false,"当前选项不可用" end
 local host=assert(self.host);local before=host.item_table
 local route=self.app.stack[#self.app.stack];local before_scroll=route and route.scroll_y or 0
 local ok,err
 if checkmark then ok,err=pcall(host.onMenuSelect,host,node,true)
 else ok,err=self.catalog:activate(node,host,hold) end
 assert(ok,err)
 if self.host==host then
  if host.item_table~=before then
   self.scrolls[#self.titles]=before_scroll;self.titles[#self.titles+1]=Native.text(node);self.scrolls[#self.titles]=0
   if route then route.scroll_y=0 end
  end
  if self.app.screen then self.app:render() end
 end
 return true
end
function Native:back()
 if self.host and #self.host.item_table_stack>0 then
  table.remove(self.titles);table.remove(self.scrolls)
  local route=self.app.stack[#self.app.stack];if route then route.scroll_y=self.scrolls[#self.titles] or 0 end
  self.host:backToUpperMenu(true);return true
 end
 self:retire();return false
end
return Native
