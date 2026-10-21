-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Restyle native informational widgets; retain their native input/timer lifecycle.
local Info=require("ui/widget/infomessage")
local Toast=require("ui/widget/notification")
local Font=require("ui/font")
local UI=require("ui/uimanager")
local P=require("einkfrontend/paint")
local N={owners=setmetatable({},{__mode="k"}),handoffs={}}
-- ShowingReader tears down the old plugin before constructing the opening
-- InfoMessage. Keep ownership through the native next-tick reader creation.
function N.handoff(owner)
 if not N.owners[owner] then return end
 local token={};N.owners[token]=true
 local finish=function() N.handoffs[token]=nil;N.detach(token) end
 local stage=UI:tickAfterNext(finish)
 N.handoffs[token]={stage=stage,finish=finish}
 return token
end
function N.cancelHandoffs()
 for token,task in pairs(N.handoffs) do
  UI:unschedule(task.stage);UI:unschedule(task.finish)
  N.owners[token]=nil;N.handoffs[token]=nil
 end
end
function N.install(owner)
 N.owners[owner]=true
 if N.info_wrapper then return end
 local info_original,toast_original=Info.init,Toast.init
 N.info_original=info_original;N.toast_original=toast_original
 N.info_wrapper=function(widget,...)
  if not next(N.owners) then return info_original(widget,...) end
  -- Explicit custom images, fixed-height reports and monospace logs keep their layout.
  local simple=not widget.image and not widget.height and not widget.monospace_font and not rawget(widget,"face")
  if simple then widget.face=Font:getFace("smallinfofontbold",P.style.label) end
  local result=info_original(widget,...)
  if simple and widget.movable and widget.movable[1] then
   local frame=widget.movable[1];frame.radius=0;frame.color=P.BB.COLOR_BLACK
   frame.bordersize=math.max(2,P.s(1.5))
   widget._eink_notice=true
  end
  return result
 end
 N.toast_wrapper=function(widget,...)
  if not next(N.owners) then return toast_original(widget,...) end
  if not rawget(widget,"face") then widget.face=Font:getFace("smallinfofontbold",P.style.label) end
  local result=toast_original(widget,...)
  widget.frame.radius=0;widget.frame.color=P.BB.COLOR_BLACK
  widget.frame.bordersize=math.max(2,P.s(1.5));widget._eink_notice=true
  -- Notification computed its stack offset before the border was thickened.
  widget[1][1].height=widget.frame:getSize().h*(widget._shown_idx-1)+widget.margin
  return result
 end
 Info.init=N.info_wrapper;Toast.init=N.toast_wrapper
end
function N.detach(owner,cancel_handoffs)
 if cancel_handoffs then N.cancelHandoffs() end
 N.owners[owner]=nil
 if next(N.owners) then return end
 if Info.init==N.info_wrapper then Info.init=N.info_original end
 if Toast.init==N.toast_wrapper then Toast.init=N.toast_original end
 N.info_wrapper=nil;N.toast_wrapper=nil
end
return N
