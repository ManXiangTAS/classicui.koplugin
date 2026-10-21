import {createRequire} from 'node:module';import {readFileSync,writeFileSync} from 'node:fs';
const require=createRequire(import.meta.url),{chromium}=require(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES+'/playwright');const meta=JSON.parse(readFileSync(process.argv[2],'utf8'));
const browser=await chromium.launch({executablePath:process.env.EINK_CHROMIUM,headless:true,args:['--no-sandbox']});const context=await browser.newContext({viewport:{width:1440,height:1000},recordVideo:{dir:meta.output+'/tutorial-recording',size:{width:1440,height:1000}}});const page=await context.newPage();
const start=Date.now(),captions=[];const step=async text=>{captions.push({time:(Date.now()-start)/1000,text});await page.evaluate(text=>{let box=document.getElementById('tutorial-caption');if(!box){box=document.createElement('div');box.id='tutorial-caption';Object.assign(box.style,{position:'fixed',zIndex:'99999',bottom:'0',left:'0',right:'0',padding:'16px 30px',background:'#18323df5',color:'white',font:'bold 23px/1.6 system-ui',textAlign:'center',pointerEvents:'none'});document.body.append(box);}box.textContent=text;},text);};
try{
 await page.goto(meta.url);await page.waitForFunction(()=>document.getElementById('message').textContent.includes('已连接 Kindle'));
 await step('网页传书实录｜这里是真实本地服务，使用原创示例 EPUB');await page.waitForTimeout(3000);
 await page.locator('#input').setInputFiles({name:'窗边的阅读时光.epub',mimeType:'application/epub+zip',buffer:readFileSync(meta.project+'/tests/transfer-fixtures/reading.epub')});await step('① 选择书籍：也可以拖入文件；EPUB 重排默认关闭');await page.waitForTimeout(3500);
 await page.mouse.move(1040,755,{steps:15});await page.locator('#advanced').click();await page.waitForFunction(()=>!document.querySelector('#useLayout').disabled);await step('② 打开高级设置：左侧是参数，右侧比较原版和精排结果');await page.waitForTimeout(4000);
 const frame=page.frameLocator('#polish');await frame.locator('#lineHeight').fill('1.85');await frame.locator('#indent').fill('2.5');await step('③ 调整行距为 1.85、缩进为 2.5 字，预览会自动更新');await page.waitForTimeout(3500);
 await frame.locator('#titleScale').scrollIntoViewIfNeeded();await step('④ 向下滚动，还能设置标题大小、自动识别标题，并选择章节');await page.waitForTimeout(3500);
 await frame.locator('#chapterSelect').selectOption('0');await page.waitForTimeout(1000);await page.locator('#useLayout').click();await step('⑤ 点击“使用此排版”，明确开启 EPUB 重排');await page.waitForTimeout(3000);
 await page.locator('#send').scrollIntoViewIfNeeded();await page.locator('#send').click();await step('⑥ 点击发送：浏览器先生成副本，再按分块发送到接收目录');await page.waitForFunction(()=>document.querySelectorAll('.status.good').length>0&&document.querySelector('#cancel').hidden);await page.waitForTimeout(2500);
 await page.locator('#files').scrollIntoViewIfNeeded();await step('⑦ 看到“已送达”，Kindle 随后自动扫描书库；原文件没有被覆盖');await page.waitForTimeout(5000);
 await page.setViewportSize({width:390,height:844});await step('手机同样可用：小屏会改成单列布局，可切换原版与精排结果');await page.waitForTimeout(4000);
 await page.setViewportSize({width:1440,height:1000});await step('传完后回 Kindle 关闭传书；休眠、退出或会话到期后需要重新扫码');await page.waitForTimeout(4000);
}finally{const video=page.video();await context.close();const file=await video.path();writeFileSync(meta.output+'/tutorial-recording.json',JSON.stringify({file,seconds:(Date.now()-start)/1000,captions,source:'Actual Chromium recording of local KOReader upload server'},null,2)+'\n');await browser.close();}
