// Script-level checks only: a small DOM substitute and a simulated HTTP peer.
// This does not launch a browser, perform network I/O or verify rendering.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const ROOT=path.resolve(process.argv[2]||path.join(__dirname,'..'));
class Element{
 constructor(tag='div'){this.tagName=tag;this.children=[];this.value='';this.style={};this.dataset={};this.listeners={};this.attrs={};this.classList={add(){},remove(){},toggle(){}};}
 append(...x){this.children.push(...x)} replaceChildren(...x){this.children=x}
 setAttribute(k,v){this.attrs[k]=v} addEventListener(k,v){this.listeners[k]=v}
 setCustomValidity(v){this.validationMessage=v} reportValidity(){return !this.validationMessage} focus(){} click(){return this.onclick?.()}
 querySelectorAll(){return []}
 set innerHTML(_){throw Error('unsafe innerHTML assignment')}
}
const token='a'.repeat(48);
const clone=x=>JSON.parse(JSON.stringify(x));
const initial={version:2,spacing:'standard',recent_count:3,tbr_count:3,heatmap_weeks:12,daily_goal_minutes:30,quote_text:'quote',quote_index:1,widgets:[{id:'currently',enabled:true,span:2},{id:'overview',enabled:true,span:2}]};
async function boot(name,flags={},storage=new Map(),hash=token){
 const elems=new Map(),requests=[],state={config:clone(initial),revision:0,dirty:true,received:0};let finish=0;
 const get=id=>{if(!elems.has(id)){const e=new Element();e.id=id;elems.set(id,e)}return elems.get(id)};
 const sessionStorage={getItem:k=>{if(flags.storageDenied)throw Error('storage blocked');return storage.get(k)||null},setItem:(k,v)=>{if(flags.storageDenied)throw Error('storage blocked');storage.set(k,v)}};
 const response=(data,status=200)=>({ok:status>=200&&status<300,status,json:async()=>clone(data),blob:async()=>new Blob(['preview'])});
 const fetch=async(url,opts={})=>{
  requests.push({url,...opts});
  if(flags.abortJSON){const r=response({});r.json=async()=>{const e=Error('cancelled');e.name='AbortError';throw e};return r}
  if(url==='/api/info')return response({chunk:flags.badChunk?Infinity:65536,directory:'/books'});
  if(url==='/api/begin'){state.received=0;return response({id:'b'.repeat(48),offset:0})}
  if(url.startsWith('/api/chunk/')){state.received+=opts.body.byteLength||opts.body.size;return response({offset:flags.badOffset?0:state.received})}
  if(url.startsWith('/api/finish/')){
   finish++;if(flags.failFinishFirst&&finish===1){const r=response({});r.json=async()=>{throw Error('dropped reply')};return r}
   return response({saved:true,name:'book.txt'});
  }
  if(url.startsWith('/api/cancel/'))return response({cancelled:true});
  if(url==='/api/preview')return response({});
  if(url==='/api/layout'&&!opts.body)return response({...state,widgets:state.config.widgets.map(w=>({id:w.id,name:w.id})),fit:{visible:2,requested:2,fits:true,omitted:[]}});
  if(url==='/api/layout'||url==='/api/save'){
   if(flags.failLayoutNext&&url==='/api/layout'){flags.failLayoutNext=false;return response({error:'temporary failure'},500)}
   const d=JSON.parse(opts.body);assert.equal(d.revision,state.revision);state.config=clone(d.config);state.revision++;state.dirty=url!=='/api/save';
   return response({revision:state.revision,dirty:state.dirty,saved:!state.dirty,fit:{visible:2,requested:2,fits:true,omitted:[]}});
  }
  return response({error:'unknown route'},404);
 };
 const location={hash:hash?'#'+hash:'',pathname:'/'};
 const ctx=vm.createContext({document:{querySelector:s=>get(s.slice(1)),getElementById:get,createElement:t=>new Element(t),createTextNode:s=>({textContent:s})},
  location,history:{replaceState(){location.hash=''}},sessionStorage,fetch,window:{addEventListener(){}},addEventListener(){},confirm:()=>true,
  TextEncoder,AbortController,Uint8Array,Blob,URL:{createObjectURL:()=> 'blob:preview',revokeObjectURL(){}},setTimeout,clearTimeout,console});
 const html=fs.readFileSync(path.join(ROOT,'einkfrontend.koplugin/resources',name),'utf8');
 const scripts=[...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map(x=>x[1]);assert.equal(scripts.length,1);
 new vm.Script(scripts[0],{filename:name}).runInContext(ctx);
 for(let i=0;i<8;i++)await new Promise(setImmediate);
 return {ctx,get,requests,storage,flags,state,run:s=>vm.runInContext(s,ctx),queue:()=>vm.runInContext('queue',ctx)};
}
const file=(name='book.txt',data='abc')=>({name,size:Buffer.byteLength(data),lastModified:1,slice:(a,b)=>new Uint8Array(Buffer.from(data).subarray(a,b))});
const checks=[];
async function test(name,fn){try{await fn();checks.push({name,passed:true})}catch(e){checks.push({name,passed:false,error:e.message})}}
(async()=>{
 await test('transfer token is removed from URL and sent only as authorization',async()=>{
  const b=await boot('send-to-device.html');assert.equal(b.run('location.hash'),'');assert.equal(b.requests[0].headers.Authorization,'Bearer '+token);
 });
 await test('file selection rejects unsupported, empty and traversal names',async()=>{
  const b=await boot('send-to-device.html');b.run('add')( [file('bad.lua'),file('empty.txt',''),file('../bad.txt')] );assert.equal(b.queue().length,0);
 });
 await test('queue deduplicates files and enforces the twenty-file bound',async()=>{
  const b=await boot('send-to-device.html');b.run('add')([file(),file()]);assert.equal(b.queue().length,1);
  b.run('add')(Array.from({length:25},(_,i)=>file('book'+i+'.txt')));assert.equal(b.queue().length,20);
 });
 await test('edited Unicode filenames stay within server byte bound',async()=>{
  const b=await boot('send-to-device.html');const name=b.run('filename')({file:file('old.epub'),title:'??����/'.repeat(100)});
  assert.ok(Buffer.byteLength(name)<=180);assert.ok(name.endsWith('.epub'));assert.ok(!/[\\/]/.test(name));
 });
 await test('price validation rejects the same long zero strings as server',async()=>{
  const b=await boot('send-to-device.html'),valid=b.run('priceValid');for(const s of ['','0','39.80','999999.99','000000000000'])assert.ok(valid(s),s);
  for(const s of ['0000000000000','-1','NaN','1.234','1000000'])assert.ok(!valid(s),s);
 });
 await test('cancel during response decoding retains AbortError identity',async()=>{
  const b=await boot('send-to-device.html');b.flags.abortJSON=true;await assert.rejects(b.run('api')('/api/test'),e=>e.name==='AbortError');
 });
 await test('blocked session storage does not break an original QR link',async()=>{
  const b=await boot('send-to-device.html',{storageDenied:true});assert.ok(b.requests.some(r=>r.url==='/api/info'));
 });
 await test('successful send uses original bytes without extra JSON encoding',async()=>{
  const b=await boot('send-to-device.html');b.run('add')([file()]);await b.get('send').onclick();assert.ok(b.queue()[0].sent);assert.equal(b.state.received,3);
  const begin=b.requests.find(r=>r.url==='/api/begin');assert.equal(JSON.parse(begin.body).author,undefined);
 });
 await test('lost finish response retries the same completion instead of restarting upload',async()=>{
  const b=await boot('send-to-device.html',{failFinishFirst:true});b.run('add')([file()]);await b.get('send').onclick();
  assert.ok(b.queue()[0].sent);assert.equal(b.requests.filter(r=>r.url==='/api/begin').length,1);assert.equal(b.requests.filter(r=>r.url.startsWith('/api/finish/')).length,2);
 });
 await test('invalid received offset is rejected and pending upload is cancelled',async()=>{
  const b=await boot('send-to-device.html',{badOffset:true});b.run('add')([file()]);await b.get('send').onclick();
  assert.ok(!b.queue()[0].sent);assert.ok(b.requests.some(r=>r.url.startsWith('/api/cancel/')));
 });
 await test('home editor can explicitly save after recovering from a failed preview update',async()=>{
  const b=await boot('home-editor.html');b.flags.failLayoutNext=true;b.run("state.quote_text='new';changed();clearTimeout(timer)");await b.run('send(false)');
  assert.equal(b.get('save').disabled,false);await b.run('send(true)');assert.equal(b.requests.filter(r=>r.url==='/api/save').length,1);
 });
 await test('home editor remembers a valid token for browser refresh',async()=>{
  const b=await boot('home-editor.html');assert.equal(b.storage.get('moye-home-token'),token);
  const c=await boot('home-editor.html',{},b.storage,'');assert.ok(c.requests.some(r=>r.url==='/api/layout'));
 });
 await test('home editor still works when session storage is unavailable',async()=>{
  const b=await boot('home-editor.html',{storageDenied:true});assert.ok(b.requests.some(r=>r.url==='/api/layout'));
 });
 const result={suite:'web-script-logic',total:checks.length,failed:checks.filter(x=>!x.passed).length,checks,browser:'NOT_RUN',network:'SIMULATED'};
 const out=path.join(ROOT,'test-results','web-logic');fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'summary.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));process.exitCode=result.failed?1:0;
})().catch(e=>{console.error(e);process.exitCode=1});
