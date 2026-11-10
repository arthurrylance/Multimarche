import {useEffect,useState} from 'react';
export type Theme='light'|'dark'|'system';
const darkQuery='(prefers-color-scheme: dark)';
const themeMode=(value:string|null):Theme=>value==='light'||value==='dark'?value:'system';
const saved=(key:string)=>{try{return localStorage.getItem(key);}catch{return null;}};
const prefers=(query:string)=>typeof window.matchMedia==='function'&&window.matchMedia(query).matches;
export default function useAppearance(){
 const[theme,setTheme]=useState<Theme>(()=>themeMode(saved('multimarche-theme')));
 const[systemDark,setSystemDark]=useState(()=>prefers(darkQuery));
 const resolvedTheme=theme==='system'?(systemDark?'dark':'light'):theme;
 const[performance,setPerformance]=useState(()=>saved('multimarche-animations')==='off');
 const[reducedMotion,setReducedMotion]=useState(()=>prefers('(prefers-reduced-motion: reduce)'));
 useEffect(()=>{document.documentElement.dataset.theme=resolvedTheme;},[resolvedTheme]);
 useEffect(()=>{try{localStorage.setItem('multimarche-theme',theme);}catch{}},[theme]);
 useEffect(()=>{document.documentElement.dataset.motion=!performance&&!reducedMotion?'on':'off';try{localStorage.setItem('multimarche-animations',performance?'off':'on');}catch{}},[performance,reducedMotion]);
 useEffect(()=>{
  const motion=window.matchMedia?.('(prefers-reduced-motion: reduce)');
  const colors=window.matchMedia?.(darkQuery);
  const updateColors=()=>setSystemDark(!!colors?.matches);
  if(colors?.addEventListener)colors.addEventListener('change',updateColors);else colors?.addListener?.(updateColors);
  updateColors();
  const update=()=>setReducedMotion(!!motion?.matches);
  const sync=(event:StorageEvent)=>{if(event.key==='multimarche-theme')setTheme(themeMode(event.newValue));if(event.key==='multimarche-animations')setPerformance(event.newValue==='off');};
  if(motion?.addEventListener)motion.addEventListener('change',update);else motion?.addListener?.(update);window.addEventListener('storage',sync);
  return()=>{if(motion?.removeEventListener)motion.removeEventListener('change',update);else motion?.removeListener?.(update);if(colors?.removeEventListener)colors.removeEventListener('change',updateColors);else colors?.removeListener?.(updateColors);window.removeEventListener('storage',sync);};
 },[]);
 return {theme,resolvedTheme,setTheme,performance,setPerformance,reducedMotion};
}
