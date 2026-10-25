-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Compact import preview with a fixed action area and independently scrolling rows.
local P=require('einkfrontend/paint');local S=P.s
local Rail=require('einkfrontend/scrollrail')
local Page={}
function Page.layout(page)
 local view=page.model.folder_import
 page.header_h=S(58);page.footer_h=S(120);page.row_h=S(54)
 page.info_h=S(172+22*#view.notices)
 page.viewport_h=math.max(S(32),page.dimen.h-page.header_h-page.info_h-page.footer_h)
 page.list_capacity=math.max(1,math.floor(page.viewport_h/page.row_h))
end
function Page.paint(page,bb,x,y)
 local view=page.model.folder_import;local w,h=page.dimen.w,page.dimen.h
 local cy=y+page.header_h;local pad=S(20)
 P.inkLabel(bb,'来源文件夹',x+pad,cy,w-2*pad,S(26),13,false,nil,'left')
 P.inkLabel(bb,view.source or '尚未选择',x+pad,cy+S(26),w-2*pad,S(30),15,false,nil,'left')
 P.rule(bb,x+pad,cy+S(63),w-2*pad,1)
 cy=cy+S(70)
 P.inkLabel(bb,view.headline,x+pad,cy,w-2*pad,S(32),22,true,nil,'left')
 P.inkLabel(bb,view.description,x+pad,cy+S(34),w-2*pad,S(26),14,false,nil,'left')
 cy=cy+S(64)
 for _,text in ipairs(view.notices) do
  P.inkLabel(bb,text,x+pad,cy,w-2*pad,S(22),13,false,nil,'left');cy=cy+S(22)
 end
 local top=y+page.header_h+page.info_h
 local content_w=w-(page.scroll_max>0 and Rail.reserve() or 0)
 if #page.model.rows>0 then
  P.inkLabel(bb,'收藏名称',x+pad,top-S(24),content_w-S(208),S(24),13,false,nil,'left')
  P.inkLabel(bb,'书籍',x+content_w-S(178),top-S(24),S(62),S(24),13,false,nil,'right')
  P.inkLabel(bb,'状态',x+content_w-S(104),top-S(24),S(84),S(24),13,false,nil,'right')
  P.rule(bb,x+pad,top,content_w-2*pad,1)
 end
 local clip=bb:viewport(x,top,content_w,page.viewport_h)
 local first=math.floor(page.scroll_y/page.row_h)+1
 local last=math.min(#page.model.rows,math.ceil((page.scroll_y+page.viewport_h)/page.row_h))
 for i=first,last do
  local row=page.model.rows[i];local ry=(i-1)*page.row_h-page.scroll_y
  P.inkLabel(clip,row.title,pad,ry,content_w-S(214),page.row_h,18,true,nil,'left')
  P.inkLabel(clip,row.count..' 本',content_w-S(178),ry,S(62),page.row_h,15,false,nil,'right')
  P.inkLabel(clip,row.import_status,content_w-S(104),ry,S(84),page.row_h,15,false,nil,'right')
  P.line(clip,pad,ry+page.row_h-1,content_w-2*pad)
 end
 clip:free()
 page.scroll_track=Rail.paint(bb,x,top,w,page.viewport_h,page.scroll_y,page.scroll_max)
 local fy=y+h-page.footer_h
 bb:paintRect(x,fy,w,page.footer_h,P.BB.COLOR_WHITE)
 P.rule(bb,x,fy,w,1)
 if view.primary then
  bb:paintRect(x+pad,fy+S(12),w-2*pad,S(48),P.BB.COLOR_BLACK)
  P.inkLabel(bb,view.primary.text,x+pad,fy+S(12),w-2*pad,S(48),18,true,P.BB.COLOR_WHITE)
  page.hits[#page.hits+1]={x=x+pad,y=fy+S(12),w=w-2*pad,h=S(48),callback=view.primary.callback,id='folder_import_primary'}
 end
 local count=#view.secondary
 for i,action in ipairs(view.secondary) do
  local bw=(w-2*pad)/count;local bx=x+pad+(i-1)*bw
  P.button(page,bb,action.text,bx,fy+S(68),bw,S(42),action.callback,
   {size=15,bold=false,align='center',id='folder_import_secondary_'..i})
 end
end
return Page
