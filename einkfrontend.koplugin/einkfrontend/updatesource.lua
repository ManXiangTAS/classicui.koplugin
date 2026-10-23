-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- WordPress relay 1.0.1: append logical paths to the complete BASE verbatim.
local S={default_base='https://www.2001330.xyz/index.php?classicui_relay='}
function S.base(value)
 assert(type(value)=='string','请输入 HTTPS 中转基础地址')
 value=value:match('^%s*(.-)%s*$')
 assert(#value>0 and #value<=1024 and not value:find('[%c\\#]'),'中转地址无效')
 local host,tail=value:match('^https://([^/?:#]+)(.*)$')
 assert(host and #host<=253 and host:match('^[%w.%-]+$') and not host:find('%.%.',1,false),'中转地址须为 HTTPS，不含账号、端口或片段')
 for label in (host..'.'):gmatch('(.-)%.') do assert(#label>0 and #label<=63 and label:match('^[%w]') and label:match('[%w]$'),'中转域名无效') end
 local query=tail:match('%?classicui_relay=$')~=nil
 local path=tail
 if query then path=tail:sub(1,#tail-#'?classicui_relay=') else assert(not tail:find('?',1,true),'只接受固定的 ?classicui_relay= 查询前缀') end
 assert(path=='' or path:match('^/[%w%._~/%-]*$'),'中转地址路径无效')
 assert(not path:find('//',1,true),'中转地址路径无效')
 for part in path:gmatch('[^/]+') do assert(part~='.' and part~='..','中转地址不能包含越界路径') end
 if not query then path=path:gsub('/+$','') end
 return 'https://'..host:lower()..path..(query and '?classicui_relay=' or '')
end
function S.url(base,path,channel)
 base=S.base(base)
 local url=base..path
 if channel then assert(channel=='stable' or channel=='testing','更新通道无效');url=url..(base:find('?',1,true) and '&' or '?')..'channel='..channel end
 return url
end
function S.allowed(url,base)
 local ok,canonical=pcall(S.base,base);if not ok or canonical~=base then return false end
 for _,channel in ipairs({'stable','testing'}) do if url==S.url(base,'/v1/classicui/manifest',channel) then return true end end
 local prefix=base..'/v1/classicui/packages/'
 if type(url)~='string' or url:sub(1,#prefix)~=prefix then return false end
 local version,digest=url:sub(#prefix+1):match('^([%d][%w%.%-]*)/([a-f0-9]+)%.zip$')
 return version~=nil and #digest==64 and #version<=64
end
function S.key(config)
 return (config.source or 'relay')..'\n'..(config.source=='github' and '' or S.base(config.relay_base or S.default_base))..'\n'..config.channel
end
return S
