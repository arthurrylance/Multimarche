import {useEffect,useState} from 'react';
export type Theme='light'|'dark';
const saved=(key:string)=>{try{return localStorage.getItem(key);}catch{return null;}};
const prefers=(query:string)=>typeof window.matchMedia==='function'&&window.matchMedia(query).matches;
export default function useAppearance(){
 const[theme,setTheme]=useState<Theme>(()=>{const value=saved('multimarche-theme');return value==='light'||value==='dark'?value:prefers('(prefers-color-scheme: dark)')?'dark':'light';});
 const[performance,setPerformance]=useState(()=>saved('multimarche-animations')==='off');
 const[reducedMotion,setReducedMotion]=useState(()=>prefers('(prefers-reduced-motion: reduce)'));
 useEffect(()=>{document.documentElement.dataset.theme=theme;try{localStorage.setItem('multimarche-theme',theme);}catch{}},[theme]);
 useEffect(()=>{document.documentElement.dataset.motion=!performance&&!reducedMotion?'on':'off';try{localStorage.setItem('multimarche-animations',performance?'off':'on');}catch{}},[performance,reducedMotion]);
 useEffect(()=>{
  const motion=window.matchMedia?.('(prefers-reduced-motion: reduce)');
  const update=()=>setReducedMotion(!!motion?.matches);
  const sync=(event:StorageEvent)=>{if(event.key==='multimarche-theme'&&(event.newValue==='light'||event.newValue==='dark'))setTheme(event.newValue);if(event.key==='multimarche-animations')setPerformance(event.newValue==='off');};
  if(motion?.addEventListener)motion.addEventListener('change',update);else motion?.addListener(update);window.addEventListener('storage',sync);
  return()=>{if(motion?.removeEventListener)motion.removeEventListener('change',update);else motion?.removeListener(update);window.removeEventListener('storage',sync);};
 },[]);
 return {theme,setTheme,performance,setPerformance,reducedMotion};
}
