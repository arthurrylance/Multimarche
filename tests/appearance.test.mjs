import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import ts from 'typescript';
const compile=file=>ts.transpileModule(readFileSync(new URL('../src/'+file,import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
function appearance({stored={},reduce=false,dark=true,blocked=false}={}){
 const values=new Map(Object.entries(stored)),state=[],effects=[],pending=[],events={},dataset={};let cursor=0,result;
 const media={matches:reduce,addEventListener:(_,fn)=>events.motion=fn,removeEventListener(){}};
 const colors={matches:dark,addEventListener:(_,fn)=>events.colors=fn,removeEventListener(){}};
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=typeof init==='function'?init():init;return[state[i],value=>state[i]=value];},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i][j])){effects[i]=deps;pending.push(fn);}}};
 const module={exports:{}};vm.runInNewContext(compile('useAppearance.ts'),{exports:module.exports,require:()=>hooks,localStorage:{getItem:k=>{if(blocked)throw Error();return values.get(k)??null;},setItem:(k,v)=>{if(blocked)throw Error();values.set(k,v);}},window:{matchMedia:q=>q.includes('reduced')?media:colors,addEventListener:(name,fn)=>events[name]=fn,removeEventListener(){}},document:{documentElement:{dataset}}});
 return{render(){cursor=0;result=module.exports.default();for(const fn of pending.splice(0))fn();return result;},values,dataset,events,media,colors};
}
test('theme and performance mode persist; OS reduced motion wins over animation preference',()=>{
 const app=appearance();let prefs=app.render();assert.equal(prefs.theme,'system');assert.equal(prefs.resolvedTheme,'dark');assert.equal(app.dataset.motion,'on');prefs.setPerformance(true);app.render();assert.equal(app.dataset.motion,'off');assert.equal(app.values.get('multimarche-animations'),'off');prefs.setTheme('light');prefs=app.render();assert.equal(app.dataset.theme,'light');prefs.setPerformance(false);app.media.matches=true;app.events.motion();app.render();assert.equal(app.dataset.motion,'off');assert.equal(app.values.get('multimarche-animations'),'on');
});
test('display preferences synchronize between tabs and work when storage is blocked',()=>{
 const app=appearance({stored:{'multimarche-theme':'invalid','multimarche-animations':'off'}});app.render();app.events.storage({key:'multimarche-theme',newValue:'light'});app.events.storage({key:'multimarche-animations',newValue:'on'});app.render();assert.equal(app.dataset.theme,'light');assert.equal(app.dataset.motion,'on');const blocked=appearance({blocked:true});const prefs=blocked.render();prefs.setPerformance(true);blocked.render();assert.equal(blocked.dataset.motion,'off');
});
test('display settings change independently of profile/password submission',()=>{
 const jsx=(type,props)=>({type,props}),module={exports:{}},changes=[];
 vm.runInNewContext(compile('AppearanceSettings.tsx'),{exports:module.exports,require:name=>name==='react/jsx-runtime'?{jsx,jsxs:jsx}:new Proxy({},{get:()=>()=>null})});
 const tree=module.exports.default({theme:'dark',setTheme:x=>changes.push(x),performance:false,setPerformance:x=>changes.push(x),reducedMotion:false});const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];const nodes=walk(tree);assert.equal(nodes.some(n=>n.type==='form'),false);const light=nodes.find(n=>n.type==='button'&&n.props.children==='Light');assert.equal(light.props.type,'button');light.props.onClick();nodes.find(n=>n.props?.role==='switch').props.onChange({target:{checked:true}});assert.deepEqual(changes,['light',true]);
});

test('System follows OS theme changes while an explicit theme remains selected',()=>{
 const app=appearance({dark:false});let prefs=app.render();assert.equal(app.dataset.theme,'light');assert.equal(app.values.get('multimarche-theme'),'system');
 app.colors.matches=true;app.events.colors();prefs=app.render();assert.equal(app.dataset.theme,'dark');
 prefs.setTheme('light');app.render();app.colors.matches=false;app.events.colors();app.render();app.colors.matches=true;app.events.colors();prefs=app.render();assert.equal(app.dataset.theme,'light');
 prefs.setTheme('system');app.render();assert.equal(app.dataset.theme,'dark');
});
