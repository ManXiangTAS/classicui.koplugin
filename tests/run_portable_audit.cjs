// Portable Lua logic checks. This is not a KOReader emulator.
const fs=require('node:fs'),path=require('node:path');
const base=process.env.FENGARI_ROOT?path.resolve(process.env.FENGARI_ROOT):path.join(path.dirname(require.resolve('fengari/package.json')),'src');
const core=require(path.join(base,'fengaricore.js')),lua=require(path.join(base,'lua.js')),aux=require(path.join(base,'lauxlib.js'));
const root=path.resolve(process.argv[2]||path.join(__dirname,'..')),mode=process.argv[3]||'audit';
if(!['audit','policy','response','upgrade','library','feedback','home_capacity'].includes(mode))throw Error('unknown portable audit mode');
function state(){
 const L=aux.luaL_newstate();
 for(const [name,file,fn] of [['_G','lbaselib','luaopen_base'],['math','lmathlib','luaopen_math'],['table','ltablib','luaopen_table'],['string','lstrlib','luaopen_string'],['coroutine','lcorolib','luaopen_coroutine']]){
  aux.luaL_requiref(L,core.to_luastring(name),require(path.join(base,file+'.js'))[fn],1);lua.lua_pop(L,1);
 }return L;
}
function run(L,text,name){
 const status=aux.luaL_loadbuffer(L,core.to_luastring(text),null,core.to_luastring(name))||lua.lua_pcall(L,0,0,0);
 if(status)throw Error(lua.lua_tojsstring(L,-1));
}
const folder=path.join(root,'einkfrontend.koplugin/einkfrontend');
const files=fs.readdirSync(folder).filter(x=>x.endsWith('.lua'));
const syntax=state(),all=files.map(x=>'einkfrontend/'+x).concat(['main.lua','_meta.lua']);
for(const file of all){
 const code=aux.luaL_loadbuffer(syntax,core.to_luastring(fs.readFileSync(path.join(root,'einkfrontend.koplugin',file),'utf8')),null,core.to_luastring('@'+file));
 if(code)throw Error(lua.lua_tojsstring(syntax,-1));lua.lua_pop(syntax,1);
}
const testSyntaxFiles=fs.readdirSync(path.join(root,'tests')).filter(x=>x.endsWith('.lua'));
for(const file of testSyntaxFiles){
 const code=aux.luaL_loadbuffer(syntax,core.to_luastring(fs.readFileSync(path.join(root,'tests',file),'utf8')),null,core.to_luastring('@tests/'+file));
 if(code)throw Error(lua.lua_tojsstring(syntax,-1));lua.lua_pop(syntax,1);
}
const sources={};for(const file of files)sources['einkfrontend/'+file.slice(0,-4)]=fs.readFileSync(path.join(folder,file),'utf8');
sources['einkfrontend/plugin']=fs.readFileSync(path.join(root,'einkfrontend.koplugin/main.lua'),'utf8');
const quote=s=>'[========['+s+']========]';
const prefix="unpack=table.unpack; package={path='',loaded={},preload={}}; _sources={"+Object.entries(sources).map(([k,v])=>'[ '+quote(k)+' ]='+quote(v)).join(',')+'}\n'+[
'function require(name)',
' if package.loaded[name]~=nil then return package.loaded[name] end',
' local loader=package.preload[name]',
" if not loader then loader=assert(load(assert(_sources[name], 'missing module '..name), '@'..name)) end",
' local v=loader(name);if v==nil then v=true end;package.loaded[name]=v;return v',
'end'].join('\n');
const L=state();run(L,prefix,'bootstrap');let result;
if(mode==='policy'){
 run(L,"POLICY_CHECKS={};local output=print;function print(v) output(v);if type(v)=='string' and v:sub(1,5)=='PASS ' then POLICY_CHECKS[#POLICY_CHECKS+1]=v:sub(6) end end",'capture-policy');
 run(L,fs.readFileSync(path.join(root,'tests/test_light_policy.lua'),'utf8'),'original-light-policy');
 lua.lua_getglobal(L,core.to_luastring('POLICY_CHECKS'));const checks=[];
 for(let i=1;i<=lua.lua_rawlen(L,-1);i++){lua.lua_rawgeti(L,-1,i);checks.push({name:lua.lua_tojsstring(L,-1),passed:true});lua.lua_pop(L,1)}
 result={suite:'original-light-policy',checks,total:checks.length,failed:0};
}else{
 run(L,fs.readFileSync(path.join(root,mode==='home_capacity'?'tests/test_home_capacity.lua':mode==='feedback'?'tests/test_device_feedback.lua':mode==='library'?'tests/test_folder_collections.lua':mode==='response'?'tests/test_light_response.lua':mode==='upgrade'?'tests/test_light_upgrade.lua':'tests/test_portable_failures.lua'),'utf8'),'portable-failure-cases');
 lua.lua_getglobal(L,core.to_luastring('AUDIT_RESULT'));result=JSON.parse(lua.lua_tojsstring(L,-1));result.suite=mode==='home_capacity'?'home-capacity':mode==='feedback'?'device-feedback':mode==='library'?'folder-collections-reader-entry':mode==='response'?'light-response':mode==='upgrade'?'light-upgrade':'portable-failures';
}
result.syntax_files=all.length+testSyntaxFiles.length;result.runtime='Fengari Lua 5.3';result.koreader='MOCKED';result.hardware='NOT_RUN';
const out=path.join(root,'test-results','portable');fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,mode+'-summary.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify({suite:result.suite,total:result.total,failed:result.failed,syntax_files:result.syntax_files}));
process.exitCode=result.failed?1:0;
