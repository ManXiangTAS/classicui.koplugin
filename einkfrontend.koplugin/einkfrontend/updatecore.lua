-- Compatibility tombstone: online update and package activation were removed.
local function removed() error('在线更新功能已移除，请完全退出 KOReader 后手动安装',0) end
return {removed=true,fetch=removed,download=removed,prepare=removed,stage=removed}
