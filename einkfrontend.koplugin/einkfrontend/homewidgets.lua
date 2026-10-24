-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Shared layout and paint pass: no widget may free a borrowed cover or draw outside its cell.
local P=require("einkfrontend/paint");local S=P.s;local B=P.BB
local Layout=require("einkfrontend/homelayout")
local Font=require("ui/font");local TextBox=require("ui/widget/textboxwidget")
local Widgets={}
local function block(bb,text,x,y,w,h,size)
 local widget=TextBox:new{text=tostring(text or ""),face=Font:getFace("smallinfofontbold",size),bold=true,width=math.max(1,w),height=h,height_adjust=true,height_overflow_show_ellipsis=true,fgcolor=B.COLOR_BLACK}
 widget:paintTo(bb,x,y);widget:free()
end
local function progress(bb,x,y,w,value)
 bb:paintBorder(x,y,w,S(7),S(1),B.COLOR_BLACK)
 if value then bb:paintRect(x+S(1),y+S(1),math.floor((w-S(2))*math.max(0,math.min(1,value))),S(5),B.COLOR_BLACK) end
end
local function cover(app,bb,book,x,y,w,h)
 local image=app.library:cover(book.file)
 if image then
  local widget=require("ui/widget/imagewidget"):new{image=image,image_disposable=false,width=w,height=h,scale_factor=0}
  widget:paintTo(bb,x,y);widget:free()
 else bb:paintBorder(x,y,w,h,S(1.5),B.COLOR_BLACK);block(bb,book.title,x+S(6),y+S(12),w-S(12),h-S(20),14) end
end
Widgets.layout=require('einkfrontend/homefit').plan
local function metrics(bb,values,labels,w,h)
 if w<S(300) then
  for i=1,#values do
   local rowh=h/#values;P.label(bb,labels[i],S(8),(i-1)*rowh,w-S(16),rowh*.5,13,true)
   P.label(bb,values[i],S(8),(i-1)*rowh+rowh*.5,w-S(16),rowh*.5,20,true)
  end
 else
  for i=1,#values do local left=(i-1)*w/#values;local cw=w/#values
   P.label(bb,values[i],left+S(8),S(12),cw-S(16),h*.48,28,true)
   P.label(bb,labels[i],left+S(8),h*.56,cw-S(16),h*.3,14,true)
   if i<#values then bb:paintRect(left+cw,S(16),S(1.5),h-S(34),B.COLOR_BLACK) end
  end
 end
end
function Widgets.paint(page,bb,frame,x,y,top,viewh)
 local app=page.app;local model=page.model.home_data;local config=app.home_layout.config
 local w,h=frame.w,frame.h;local fy=frame.y-page.scroll_y
 local visible_y=math.max(0,fy);local visible_h=math.min(viewh,fy+h)-visible_y
 if visible_h<=0 then return end
 -- Paint to an owned temporary buffer, then blit only the visible cell. Negative
 -- coordinates are never passed to viewport(), including while scrolling.
 local cell=B.new(w,h,bb:getType());cell:paintRect(0,0,w,h,B.COLOR_WHITE)
 local function hit(id,left,cy,cw,ch,fn,hold)
  local hy=math.max(0,fy+cy);local hh=math.min(viewh,fy+cy+ch)-hy
  if hh>0 then page.hits[#page.hits+1]={x=x+frame.x+left,y=top+hy,w=cw,h=hh,callback=fn,hold_callback=hold,id=id} end
 end
 if frame.id=="reading_return" then
  require('einkfrontend/returnwidget').paint(cell,w,h,model.reading_return)
  hit('home_reading_return',0,0,w,h,function() app:go('reading_return') end)
 elseif frame.id=="currently" then
  if model.book then
   local book=model.book;local narrow=w<S(300);local compact=h<S(208)
   local cw=math.min(S(126),w*(narrow and .28 or .24));local ch=math.min(h-S(24),math.floor(cw*1.45))
   cw=math.min(cw,math.floor(ch/1.45))
   cover(app,cell,book,0,S(12),math.floor(cw),ch)
   local tx=math.floor(cw)+S(16);local tw=w-tx;local titleh=compact and S(40) or S(60)
   block(cell,book.title,tx,S(12),tw,titleh,narrow and 16 or 20)
   local author_y=S(12)+titleh
   P.label(cell,book.authors or "作者未知",tx,author_y,tw,S(24),13,true)
   local pct=model.percent and math.floor(model.percent*100).."%" or model.status
   P.label(cell,"阅读进度："..pct,tx,author_y+S(26),tw,S(26),narrow and 13 or 16,true)
   local progressw=not narrow and model.detail and tw*.54 or tw
   progress(cell,tx,author_y+S(54),progressw,model.percent)
   if not narrow and model.detail and model.detail.book_remaining then
    P.label(cell,'剩余 '..model.detail.book_remaining,tx+tw*.58,author_y+S(26),tw*.42,S(26),13,true)
   end
   local chapter=model.detail and model.detail.chapter_percent
   if h>=S(208) then
    P.label(cell,chapter and "当前章节："..math.floor(chapter*100).."%" or "章节进度：暂无数据",tx,author_y+S(72),tw,S(24),13,true)
    progress(cell,tx,author_y+S(101),progressw,chapter)
    if not narrow and model.detail and model.detail.chapter_remaining then
     P.label(cell,'剩余 '..model.detail.chapter_remaining,tx+tw*.58,author_y+S(72),tw*.42,S(24),13,true)
    end
   end
   hit("home_continue",0,0,w,h,function() app:openRecentBook(book.file) end,function() app:go('book',book) end)
  else P.label(cell,"还没有阅读记录",0,S(12),w,h-S(24),18,true,"center") end
 elseif frame.id=="reading_stats" then
  local seconds,sessions,pages=model.book_seconds,model.sessions,model.book_pages
  metrics(cell,{seconds and string.format("%.1f",seconds/3600) or "—",seconds and sessions and sessions>0 and tostring(math.floor(seconds/sessions/60+.5)) or "—",seconds and seconds>0 and pages and string.format("%.1f",pages/(seconds/60)) or "—"},
   {"本书阅读时数","平均每次分钟","平均每分钟页数"},w,h-S(4))
 elseif frame.id=="overview" then
  P.label(cell,"书库概览",0,0,w,S(34),18,true)
  local inner=cell:viewport(0,S(40),w,h-S(44))
  metrics(inner,{model.total>0 and tostring(math.floor(model.completed/model.total*100+.5)).."%" or "—",tostring(model.completed),model.total_seconds and string.format("%.1f",model.total_seconds/3600) or "—"},
   {"书库完成比例","已完成阅读","累计阅读时数"},w,h-S(44));inner:free()
 elseif frame.id=="recent" or frame.id=="tbr" then
  P.label(cell,Layout.by_id[frame.id].name,0,0,w,S(34),18,true)
  local books=model[frame.id] or {};local limit=Layout.shelfCount(config,frame.id);local count=math.min(#books,limit)
  if count==0 then P.label(cell,frame.id=="recent" and "暂无最近阅读" or "暂无待读书籍",0,S(50),w,S(70),16,true) end
  local columns=w<S(300) and 2 or limit;local cw=(w-S(10)*(columns-1))/columns
  local rows=math.ceil(limit/columns);local rowh=math.floor((h-S(42))/rows)
  for i=1,count do
   local book=books[i];local bx=math.floor((i-1)%columns*(cw+S(10)));local by=S(38)+math.floor((i-1)/columns)*rowh
   local ch=math.min(S(140),rowh-S(32));local coverw=math.min(math.floor(cw),math.floor(ch*.70));ch=math.floor(coverw/0.70)
   cover(app,cell,book,bx,by,coverw,ch)
   block(cell,book.title,bx,by+ch+S(3),math.floor(cw),S(24),12)
   hit("home_"..frame.id.."_"..i,bx,by,math.floor(cw),rowh-S(2),function() app:openRecentBook(book.file) end,function() app:go('book',book) end)
  end
 elseif frame.id=="quote" then
  P.label(cell,"名人名言",0,0,w,S(32),18,true)
  local quotes=Layout.quotes(config.quote_text);local quote=quotes[(config.quote_index-1)%math.max(1,#quotes)+1]
  if quote then block(cell,quote.text,0,S(36),w,h-S(68),h<S(150) and 15 or 18);P.label(cell,quote.author,0,h-S(30),w,S(26),13,true)
  else P.label(cell,"轻点铅笔，添加自己的名言",0,S(36),w,h-S(48),16,true) end
  hit("home_quote_next",0,0,w,h,function() local ok,why=app.home_layout:nextQuote();if ok then app:render() else app:message(why) end end)
 elseif frame.id=="clock" then
  P.label(cell,os.date("%H:%M"),0,S(4),w,h-S(36),h<S(110) and 28 or 34,true)
  P.label(cell,os.date("%Y-%m-%d"),0,h-S(32),w,S(28),14,true)
  hit("home_clock_settings",0,0,w,h,function() app:go("clock_settings") end)
 else
  require("einkfrontend/homestatwidgets").paint(cell,frame.id,w,h,model.dashboard,config,hit,function(text) app:message(text) end,
   function() app:go("home_widget","daily_goal") end)
 end
 P.rule(cell,0,h-S(2),w,1.5)
 bb:blitFrom(cell,frame.x,visible_y,0,visible_y-fy,w,visible_h);cell:free()
end
function Widgets.home(page,bb,x,y)
 local app=page.app;local w,h=page.dimen.w,page.dimen.h
 local top=y+S(96);local viewh=h-S(168);page.viewport_h=viewh
 local frames,content_h,fit=Widgets.layout(app.home_layout.config,w,viewh)
 page.widget_frames=frames;page.home_content_h=content_h;page.home_fit=fit
 page.scroll_max=0;page.scroll_y=0;page.model.route.scroll_y=0;page.scroll_track=nil
 local clip=bb:viewport(x,top,w,viewh)
 if #frames==0 then P.label(clip,"点击“主页”旁的铅笔，添加部件",S(20),S(50),w-S(40),S(100),18,true,"center") end
 for _,frame in ipairs(frames) do Widgets.paint(page,clip,frame,x,y,top,viewh) end
 clip:free()
 if not fit.fits then
  P.inkLabel(bb,'还有 '..#fit.omitted..' 个部件未放入本屏，点铅笔调整',x+S(20),top+viewh-S(30),w-S(40),S(30),13,true,nil,'center')
 end
end
return Widgets
