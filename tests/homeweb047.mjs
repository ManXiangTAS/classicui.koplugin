import {createRequire} from 'node:module';import {readFileSync,writeFileSync} from 'node:fs';
const require=createRequire(import.meta.url),{chromium}=require(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES+'/playwright');
const meta=JSON.parse(readFileSync(process.argv[2],'utf8'));const report={checks:[],device:'NOT_RUN',backend:'Chromium + real KOReader LuaSocket HTTP server'};
const browser=await chromium.launch({executablePath:process.env.EINK_CHROMIUM,headless:true,args:['--no-sandbox']});const context=await browser.newContext({viewport:{width:390,height:844}});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
const check=(name,truth)=>{if(!truth)throw Error(name);report.checks.push({name,status:'PASS'});};
try{
 await page.goto(meta.url);await page.waitForFunction(()=>document.getElementById('status').textContent.includes('可以开始编辑'));
 check('Token is removed from browser address after bootstrap',!new URL(page.url()).hash);
 check('All thirteen modules are accessible',await page.locator('article').count()===13);
 await page.locator('#search').fill('热力图');check('Browser search filters modules in place',await page.locator('article').count()===1);await page.locator('#search').fill('');
 const first=page.locator('article input[type=checkbox]').first();const before=await first.isChecked();await first.click();await page.waitForFunction(()=>document.getElementById('status').textContent.includes('预览已更新'));
 check('Browser changes produce a native preview before saving',!(await page.locator('#save').isDisabled())&&await page.locator('#preview').evaluate(i=>i.naturalWidth>0));
 await page.locator('#daily_goal_minutes').fill('45');await page.locator('#quote_text').fill('<img src=x onerror=alert(1)>｜自己的摘记');await page.locator('#save').click();await page.waitForFunction(()=>document.getElementById('status').textContent==='已保存到 Kindle');
 check('Save commits edited values to device',await page.locator('#save').isDisabled());check('Custom text is handled without executing markup',errors.length===0);
 const response=await context.request.get(meta.origin+'/api/layout',{headers:{Authorization:'Bearer '+meta.token}}),layout=await response.json();check('HTTP readback matches toggles quote and daily goal',layout.config.daily_goal_minutes===45&&layout.config.widgets[0].enabled!==before&&layout.config.quote_text.startsWith('<img'));
 const noauth=await context.request.get(meta.origin+'/api/layout');check('Unauthenticated network request is rejected',noauth.status()===401);
 const badOrigin=await context.request.get(meta.origin+'/api/layout',{headers:{Authorization:'Bearer '+meta.token,Origin:'http://foreign.example'}});check('Cross origin network request is rejected',badOrigin.status()===403);
 const badHost=await context.request.get(meta.origin+'/api/layout',{headers:{Authorization:'Bearer '+meta.token,Host:'foreign.example'}});check('Foreign Host network request is rejected',badHost.status()===403);
 const wrongtype=await context.request.post(meta.origin+'/api/layout',{headers:{Authorization:'Bearer '+meta.token,'Content-Type':'text/plain'},data:'{}'});check('Non JSON mutation is rejected',wrongtype.status()===415);
 await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:meta.output+'/phone-editor.png',fullPage:true});await page.setViewportSize({width:1280,height:900});await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:meta.output+'/desktop-editor.png',fullPage:true});check('Mobile and desktop previews render without JavaScript errors',errors.length===0);
 report.failures=0;writeFileSync(meta.output+'/browser-summary.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({checks:report.checks.length,failures:0}));
} finally{await browser.close();}
