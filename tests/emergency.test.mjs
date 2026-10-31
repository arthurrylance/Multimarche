import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import ts from 'typescript';
import {EMERGENCY_URL,recordEscape,shouldRedirectForEmergency} from '../src/interactions.mjs';
const source=readFileSync(new URL('../src/useEmergencyRedirect.ts',import.meta.url),'utf8').replace(/^import[^\n]*\n/gm,'').replace('export default function','function')+'\nuseEmergencyRedirect(hide);';
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText;
function setup({token='',stored=null,signal={version:0,triggered_at:null}}={}){
 const window=new EventTarget(),document=new EventTarget(),values=new Map(stored===null?[]:[['multimarche-emergency-version',String(stored)]]),requests=[];let cleanup,realtime,url,hidden=0;
 window.location={replace:value=>{url=value;}};document.visibilityState='visible';
 const channel={on(_type,_filter,fn){realtime=fn;return this;},subscribe(){return this;}};
 const supabase={auth:{getSession:async()=>({data:{session:token?{access_token:token}:null}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},channel:()=>channel,removeChannel:async()=>{}};
 const fetch=async(url,options)=>{requests.push({url,options});return new Response(JSON.stringify(options?.method==='POST'?1:[signal]),{status:200,headers:{'content-type':'application/json'}});};
 vm.runInNewContext(compiled,{useEffect:fn=>{cleanup=fn();},supabase,supabaseUrl:'https://backend.example.test',supabasePublishableKey:'public-key',EMERGENCY_URL,recordEscape,shouldRedirectForEmergency,window,document,localStorage:{getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v)},hide:()=>hidden++,fetch,AbortSignal,Date,Math,Number,setInterval:()=>1,clearInterval(){},setTimeout,clearTimeout});
 const escape=()=>{const e=new Event('keydown',{cancelable:true});Object.assign(e,{key:'Escape',repeat:false});window.dispatchEvent(e);};
 return {escape,cleanup:()=>cleanup(),realtime:s=>realtime({new:s}),requests,values,get url(){return url;},get hidden(){return hidden;}};
}
const settle=()=>new Promise(resolve=>setImmediate(resolve));
test('signed-in emergency immediately hides and sends an authenticated keepalive broadcast',async()=>{
 const app=setup({token:'fixture-session-token'});try{await settle();app.escape();app.escape();assert.equal(app.url,undefined);app.escape();app.escape();await settle();const posts=app.requests.filter(r=>r.options?.method==='POST');assert.equal(posts.length,1);assert.equal(posts[0].options.keepalive,true);assert.equal(posts[0].options.headers.authorization,'Bearer fixture-session-token');assert.equal(posts[0].url,'https://backend.example.test/rest/v1/rpc/trigger_emergency');assert.equal(app.url,EMERGENCY_URL);assert.ok(app.hidden>0);}finally{app.cleanup();}
});
test('guests redirect locally without permission to send a global trigger',async()=>{
 const app=setup();try{await settle();app.escape();app.escape();app.escape();assert.equal(app.url,EMERGENCY_URL);assert.equal(app.requests.filter(r=>r.options?.method==='POST').length,0);}finally{app.cleanup();}
});
test('another tab receives a signal and remembers it before leaving',async()=>{
 const app=setup({stored:0});try{await settle();app.realtime({version:1,triggered_at:new Date().toISOString()});assert.equal(app.url,EMERGENCY_URL);assert.equal(app.values.get('multimarche-emergency-version'),'1');}finally{app.cleanup();}
});
