const point=cell=>({x:cell%20*20+10,y:Math.floor(cell/20)*20+10});
const path=points=>points.map((p,i)=>`${i?'L':'M'}${p.x} ${p.y}`).join(' ');
export function snakeFrame(previous,next,progress){
 const target=next.map(point),before=previous.map(point),t=Math.max(0,Math.min(1,progress));
 const follows=next.length>=previous.length&&next.length<=previous.length+1&&next.slice(1).every((cell,i)=>cell===previous[i]);
 if(!follows||!before.length||Math.abs(target[0].x-before[0].x)+Math.abs(target[0].y-before[0].y)!==20)return{d:path(target),head:target[0]};
 const head={x:before[0].x+(target[0].x-before[0].x)*t,y:before[0].y+(target[0].y-before[0].y)*t};
 if(next.length>previous.length)return{d:path([head,...before]),head};
 const tail=before.at(-1),toward=before.at(-2)??target[0];
 return{d:path([head,...before.slice(0,-1),{x:tail.x+(toward.x-tail.x)*t,y:tail.y+(toward.y-tail.y)*t}]),head};
}
