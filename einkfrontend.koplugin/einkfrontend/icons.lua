-- Original mapping. Icons: Google Material Symbols Sharp, Apache-2.0.
-- Original SVGs and complete provenance/license travel with the plugin.
local Icons={}
local base=debug.getinfo(1,"S").source:sub(2):match("^(.*)/").."/../resources/icons/sharp/"
Icons.names={
 home="home",["book.opened"]="library_books",["appbar.filebrowser"]="folder",
 ["appbar.settings"]="settings",wifi="wifi",["appbar.menu"]="toc",
 bookmark="bookmark",["appbar.search"]="search",refresh="refresh",edit="edit",statistics="bar_chart",
 close="close",["chevron.left"]="chevron_left",["chevron.right"]="chevron_right",
 ["chevron.up"]="expand_less",["chevron.down"]="expand_more",
 ["control.expand"]="add",["control.collapse"]="remove",
 ["appbar.textsize"]="format_size",["appbar.contrast"]="contrast",["appbar.navigation"]="navigation",
 ["appbar.rotation"]="screen_rotation",["cre.render.reload.alpha"]="refresh",
 plugins="extension",device="devices",maintenance="build",misc="category",reading="menu_book",
 brightness="light_mode",check="check",more="more_horiz",night="dark_mode",sync="sync",
}
-- Optical size corrections are context-specific, not a change to slot geometry.
-- Preserve the original paths/aspect ratios; the visible-ink pass keeps centers.
Icons.profiles={
 settings={menu_book=.94,contrast=.92,navigation=.90,folder=.90,search=1.04,wifi=1.06,
  extension=.90,devices=1.02,category=.92,build=.94,settings=.93},
 controls={wifi=1.00,dark_mode=1.05,screen_rotation=.85,refresh=1.13,settings=.95,sync=.96},
 toolbar={home=.92,library_books=.96,toc=.98,bookmark=.93,search=1.06,refresh=1.10,edit=1.02,
  bar_chart=.98,close=.96,chevron_left=.94,chevron_right=.94,expand_less=.96,expand_more=.96},
}
function Icons.size(name,size,group)
 local profile=Icons.profiles[group or "toolbar"] or {}
 return math.max(1,math.floor(size*(profile[Icons.names[name]] or 1)+.5))
end
function Icons.file(name) return Icons.names[name] and base..Icons.names[name]..".svg" end
return Icons
