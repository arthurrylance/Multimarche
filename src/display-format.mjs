import {SCHOOL_ZONE} from './ending-times.mjs';
const dateFormat=new Intl.DateTimeFormat('en-GB',{timeZone:SCHOOL_ZONE,day:'2-digit',month:'2-digit',year:'numeric'});
const timeFormat=new Intl.DateTimeFormat('en-GB',{timeZone:SCHOOL_ZONE,hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
const shareFormat=new Intl.NumberFormat('en-GB',{minimumFractionDigits:2,maximumFractionDigits:2});
export function formatShares(value){return shareFormat.format(Number(value));}
export function formatDate(value){const date=new Date(value);return Number.isFinite(date.getTime())?dateFormat.format(date):'—';}
export function formatDateTime(value){const date=new Date(value);return Number.isFinite(date.getTime())?`${dateFormat.format(date)} ${timeFormat.format(date)}`:'—';}
export function dateInputDisplay(value){const match=/^(\d{4})-(\d{2})-(\d{2})$/.exec(value);return match?`${match[3]}/${match[2]}/${match[1]}`:'';}
export function parseDateInput(value){
 const match=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value);if(!match)return null;
 const day=Number(match[1]),month=Number(match[2]),year=Number(match[3]),date=new Date(Date.UTC(year,month-1,day));
 if(year<1000||date.getUTCFullYear()!==year||date.getUTCMonth()!==month-1||date.getUTCDate()!==day)return null;
 return `${match[3]}-${match[2]}-${match[1]}`;
}

export function dateInputDraft(value){const digits=value.replace(/[^0-9]/g,'').slice(0,8);return digits.slice(0,2)+(digits.length>2?`/${digits.slice(2,4)}`:'')+(digits.length>4?`/${digits.slice(4)}`:'');}
