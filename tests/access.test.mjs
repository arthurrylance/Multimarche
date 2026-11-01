import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import ts from 'typescript';
const source=readFileSync(new URL('../src/App.tsx',import.meta.url),'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function app(session=null){
 let current,cursor=0;const root={state:[],effects:[]},child={state:[],effects:[]},pending=[],calls=[];let tree;
 const hooks={useState:init=>{const i=cursor++,instance=current;if(!(i in instance.state))instance.state[i]=typeof init==='function'?init():init;return[instance.state[i],value=>{instance.state[i]=typeof value==='function'?value(instance.state[i]):value;}];},useRef:init=>{const i=cursor++;return current.state[i]??={current:init};},useCallback:fn=>{cursor++;return fn;},useEffect:(fn,deps)=>{const i=cursor++,instance=current;if(!instance.effects[i]||deps?.some((v,j)=>v!==instance.effects[i].deps[j])){instance.effects[i]={deps};pending.push(fn);}},lazy:()=>()=>null,Suspense:()=>null};
 const supabase={auth:{getSession:async()=>({data:{session},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},rpc:name=>{calls.push(name);return new Promise(()=>{});},from:name=>{calls.push(name);throw new Error('Guest attempted to read data');},channel:()=>({on(){return this;},subscribe(){return this;}}),removeChannel:async()=>{}};
 const jsx=(type,props,key)=>({type,props:props??{},key}),module={exports:{}};
 const dummy={default:()=>null};
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx,Fragment:'fragment'}:name==='./useAppearance'?{default:()=>({theme:'dark',setTheme(){},performance:false,setPerformance(){},reducedMotion:false})}:name==='./db'?{supabase}:name==='lucide-react'?new Proxy({},{get:()=>()=>null}):dummy,localStorage:{getItem:()=> 'dark',setItem(){}},document:{documentElement:{dataset:{}}},window:{},Date,Set,Map,setTimeout,clearTimeout,setInterval:()=>1,clearInterval:()=>{}});
 const render=(fn=module.exports.default,props={},instance=root)=>{current=instance;cursor=0;tree=fn(props);for(const effect of pending.splice(0))effect();return tree;};
 const nodes=node=>node==null||typeof node!=='object'?[]:Array.isArray(node)?node.flatMap(nodes):[node,...nodes(node.props?.children)];
 const text=node=>node==null||typeof node==='boolean'?'':typeof node!=='object'?String(node):Array.isArray(node)?node.map(text).join(''):text(node.props?.children);
 return{calls,render,nodes:()=>nodes(tree),text:()=>text(tree),form:()=>{const form=nodes(tree).find(n=>typeof n.type==='function'&&n.type.name==='AuthForm');return()=>render(form.type,form.props,child);}};
}

test('signed-out users only see a login/invite screen and trigger no private data reads',async()=>{
 const guest=app();guest.render();await settle();guest.render();assert.deepEqual(guest.calls,[]);assert.ok(guest.nodes().some(n=>n.props.className==='auth-shell'));assert.equal(guest.nodes().some(n=>n.props.className==='market-grid'||n.props.className==='main-nav'),false);assert.doesNotMatch(guest.text(),/Markets Preview|Leaderboard|Your bets|Krainova/);
 const form=guest.form();form();const fields=guest.nodes().filter(n=>n.type==='input');assert.equal(fields[0].props.placeholder,'Your username');assert.equal(fields[1].props.placeholder,'Your password');const invite=guest.nodes().find(n=>n.type==='button'&&n.props.children==='Use invite code');invite.props.onClick();form();assert.ok(guest.nodes().some(n=>n.type==='input'&&n.props.placeholder==='Invite code'));
});
test('an unverified cached login does not expose navigation or market content while membership is checked',async()=>{
 const member=app({user:{id:'pending-member'}});member.render();await settle();member.render();assert.deepEqual(member.calls,['is_member']);assert.equal(member.nodes().some(n=>n.props.className==='market-grid'||n.props.className==='main-nav'),false);assert.match(member.text(),/Loading your account/);
});
