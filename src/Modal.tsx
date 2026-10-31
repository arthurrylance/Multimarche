import {useEffect,useRef} from 'react';
import type {ReactNode} from 'react';
import {X} from 'lucide-react';
import {createPortal} from 'react-dom';
export default function Modal({title,children,onClose,wide=false}:{title:string;children:ReactNode;onClose:()=>void;wide?:boolean}){
 const ref=useRef<HTMLDivElement>(null);
 useEffect(()=>{const prev=document.activeElement as HTMLElement;const old=document.body.style.overflow;document.body.style.overflow='hidden';ref.current?.focus();const handle=(e:KeyboardEvent)=>{if(e.key==='Escape')onClose();if(e.key==='Tab'){const a=ref.current?.querySelectorAll<HTMLElement>('button,input,textarea,select,a[href]');if(!a?.length)return;const first=a[0],last=a[a.length-1];if(e.shiftKey&&(document.activeElement===first||document.activeElement===ref.current)){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}};document.addEventListener('keydown',handle);return()=>{document.body.style.overflow=old;document.removeEventListener('keydown',handle);prev?.focus();};},[onClose]);
 return createPortal(<div className="overlay" onMouseDown={e=>{if(e.target===e.currentTarget)onClose();}}><div role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} ref={ref} className={`modal ${wide?'wide':''}`}><div className="modal-head"><h2>{title}</h2><button className="icon-button" onClick={onClose} aria-label="Close dialog"><X size={20}/></button></div>{children}</div></div>,document.body);
}

