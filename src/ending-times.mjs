export const SCHOOL_ZONE='Europe/Zurich';
export const SCHOOL_ENDINGS=[
 {label:'P1',name:'End of P1',time:'09:00'},
 {label:'P2',name:'End of P2',time:'09:50'},
 {label:'P3',name:'End of P3',time:'10:30'},
 {label:'Recess',name:'End of first recess',time:'10:50'},
 {label:'P4',name:'End of P4',time:'11:30'},
 {label:'P5',name:'End of P5',time:'12:15'},
 {label:'P6',name:'End of P6',time:'13:00'},
 {label:'Lunch',name:'End of lunch',time:'13:35'},
 {label:'P8',name:'End of P8',time:'14:20'},
 {label:'P9',name:'End of P9',time:'15:05'},
 {label:'School day',name:'End of the school day',time:'15:50'},
];
const clock=new Intl.DateTimeFormat('en-GB',{timeZone:SCHOOL_ZONE,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
function parts(now){return Object.fromEntries(clock.formatToParts(new Date(now)).filter(p=>p.type!=='literal').map(p=>[p.type,p.value]));}
export function schoolDate(now=Date.now()){const p=parts(now);return `${p.year}-${p.month}-${p.day}`;}
function addDay(day){const at=new Date(`${day}T12:00:00Z`);at.setUTCDate(at.getUTCDate()+1);return at.toISOString().slice(0,10);}
export function schoolDateTime(local){
 const match=/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(local);if(!match)throw new Error('Choose a closing date and time.');
 const[,year,month,day,hour,minute]=match,target=Date.UTC(+year,+month-1,+day,+hour,+minute);let at=target;
 for(let i=0;i<3;i++){const p=parts(at);at+=target-Date.UTC(+p.year,+p.month-1,+p.day,+p.hour,+p.minute);}
 const p=parts(at);if(`${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`!==local)throw new Error('Choose a valid time in Europe/Zurich.');
 return new Date(at);
}
export function suggestedSchoolDate(now=Date.now()){
 let day=schoolDate(now),weekday=new Date(`${day}T12:00:00Z`).getUTCDay();
 if(weekday>0&&weekday<6&&schoolDateTime(`${day}T15:50`).getTime()>now)return day;
 do{day=addDay(day);weekday=new Date(`${day}T12:00:00Z`).getUTCDay();}while(weekday===0||weekday===6);
 return day;
}
export function resolveEnding(value,now=Date.now()){
 let date;
 if(value.kind==='interval'){
  if(!Number.isFinite(value.minutes)||value.minutes<1||value.minutes>525600)throw new Error('Choose an interval of 1 minute to 1 year.');
  date=new Date(now+value.minutes*60000);
 }else if(value.kind==='tomorrow'){
  const p=parts(now);date=schoolDateTime(`${addDay(schoolDate(now))}T${p.hour}:${p.minute}`);
 }else date=schoolDateTime(value.local);
 if(!Number.isFinite(date.getTime())||date.getTime()<=now)throw new Error('Choose a future ending time.');
 return date;
}
