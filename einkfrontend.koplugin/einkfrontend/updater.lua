-- Compatibility tombstone: overwrites the former updater during manual upgrades.
-- No timers, workers, network calls or installation actions remain.
local function noop() return false end
return {removed=true,attach=noop,detach=noop,suspend=noop,resume=noop,check=noop,
 prepare=noop,run=noop,set=noop,cancel=noop,schedule=noop,render=noop,
 config=function() return {auto_check=false,auto_install=false} end,state=function() return {} end}
