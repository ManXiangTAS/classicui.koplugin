-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Pure curve and bounded local preferences; no device or timer dependencies.
local C={}
function C.finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
function C.lux(v) return C.finite(v) and v>=0 and v<=200000 end
function C.clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
C.default_threshold=10000
function C.base(lux,anchor,lo,hi,options)
 if not C.lux(lux) or not C.finite(anchor) or not C.finite(lo) or not C.finite(hi) or hi<=lo or anchor<lo or anchor>hi then return nil end
 options=options or {};local daylight=options.daylight or lo;local threshold=options.threshold or C.default_threshold
 if not C.finite(daylight) or daylight<lo or daylight>anchor or not C.finite(threshold) or threshold<100 or threshold>200000 then return nil end
 if lux<=5 then return anchor end
 if lux>=threshold then return daylight end
 -- Normalize above the dark sensor noise floor; 5 -> 6 lux has no jump.
 local position=(math.log(1+lux)-math.log(6))/(math.log(1+threshold)-math.log(6))
 return C.clamp(anchor+(daylight-anchor)*position,daylight,anchor)
end
function C.clean(memories,lo,hi)
 local clean={}
 if type(memories)=='table' then
  -- Bound both work and persisted history, including malformed settings.
  for i=1,math.min(#memories,12) do
   local p=memories[i]
   if type(p)=='table' and C.lux(p.lux) and C.finite(p.level) and p.level%1==0 and p.level>=lo and p.level<=hi then
    clean[#clean+1]={lux=p.lux,level=p.level}
   end
  end
 end
 table.sort(clean,function(a,b) return a.lux<b.lux end)
 for i=#clean,2,-1 do if math.log(1+clean[i].lux)-math.log(1+clean[i-1].lux)<.05 then table.remove(clean,i-1) end end
 return clean
end
function C.remember(memories,lux,level,lo,hi)
 if not C.lux(lux) or not C.finite(level) or level%1~=0 or level<=lo or level>hi then return nil end
 local result=C.clean(memories,lo,hi)
 for i=#result,1,-1 do if math.abs(math.log(1+result[i].lux)-math.log(1+lux))<.45 then table.remove(result,i) end end
 -- Keep recent corrections when the bounded history fills up.
 if #result>=12 then
  local farthest=1
  for i=2,#result do if math.abs(math.log(1+result[i].lux)-math.log(1+lux))>math.abs(math.log(1+result[farthest].lux)-math.log(1+lux)) then farthest=i end end
  table.remove(result,farthest)
 end
 result[#result+1]={lux=lux,level=level}
 table.sort(result,function(a,b) return a.lux<b.lux end)
 return result
end
function C.target(lux,anchor,lo,hi,memories,options)
 local base=C.base(lux,anchor,lo,hi,options);if not base then return nil end
 local x=math.log(1+lux);local points=C.clean(memories,lo,hi);local delta=0
 local function correction(p) return p.level-C.base(p.lux,anchor,lo,hi,options) end
 if #points>0 then
  local first,last=points[1],points[#points]
  if lux<=first.lux then delta=correction(first)*math.max(0,1-(math.log(1+first.lux)-x)/1.5)
  elseif lux>=last.lux then delta=correction(last)*math.max(0,1-(x-math.log(1+last.lux))/1.5)
  else
   for i=2,#points do
    local a,b=points[i-1],points[i]
    if lux<=b.lux then
     local t=(x-math.log(1+a.lux))/(math.log(1+b.lux)-math.log(1+a.lux))
     -- Local corrections taper back to the base across large unobserved gaps.
     local da=correction(a)*math.max(0,1-(x-math.log(1+a.lux))/1.5)
     local db=correction(b)*math.max(0,1-(math.log(1+b.lux)-x)/1.5)
     if math.log(1+b.lux)-math.log(1+a.lux)<=1.5 then delta=correction(a)*(1-t)+correction(b)*t
     else delta=da+db end
     break
    end
   end
  end
 end
 return C.clamp(math.floor(base+delta+.5),lo,hi)
end
return C
