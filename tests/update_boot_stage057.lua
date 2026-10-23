require('setupkoenv');package.path='plugins/einkfrontend.koplugin/?.lua;'..package.path
local B=require('einkfrontend/updateboot');local C=require('einkfrontend/updatecore')
local root=assert(os.getenv('EINK_BOOT_TARGET'));B.mkdir(B.work(root))
local release=require('json').decode(B.read(os.getenv('EINK_BOOT_RELEASE')))
C.stage(root,os.getenv('EINK_BOOT_ARCHIVE'),release)
if os.getenv('EINK_BOOT_MODE')=='interrupt' then
 -- Interrupt after every new file, including main.lua, has been replaced.
 local manifest=B.checkStage(root);local count=1;for _ in pairs(manifest.files) do count=count+1 end
 assert(not pcall(B.apply,root,function(i) if i==count then error('simulated process stop after main replacement') end end))
 assert(B.load(B.work(root),'journal.json').phase=='applying')
elseif os.getenv('EINK_BOOT_MODE')=='tamper' then B.atomic(B.work(root)..'/next','einkfrontend/version.lua',"return 'tampered'") end
os.exit(0)
