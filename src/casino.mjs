export const wheel=[0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26];
export const redNumbers=new Set([1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]);
export const multipliers=[8,3,1.5,.7,.4,.7,1.5,3,8];
export function cardFace(card){if(card===null)return{rank:'',suit:'',red:false};if(!Number.isInteger(card)||card<0||card>51)throw Error('Invalid card');const suit=card%4;return{rank:['A','2','3','4','5','6','7','8','9','10','J','Q','K'][Math.floor(card/4)],suit:['♠','♥','♦','♣'][suit],red:suit===1||suit===2};}
export function wheelRotation(number){const index=wheel.indexOf(number);return index<0?0:1800+(360-index*360/37)%360;}
export function wheelWedge(index){const a=(index-.5)*2*Math.PI/37-Math.PI/2,b=(index+.5)*2*Math.PI/37-Math.PI/2;return `M150 150L${150+138*Math.cos(a)} ${150+138*Math.sin(a)}A138 138 0 0 1 ${150+138*Math.cos(b)} ${150+138*Math.sin(b)}Z`;}
export function plinkoPath(bits){let x=150;const points=['M150 12'];bits.forEach((bit,i)=>{if(bit!==0&&bit!==1)throw Error('Invalid path');const before=x;x+=bit===1?15:-15;points.push(`Q${before} ${40+i*26} ${x} ${53+i*26}`);});points.push(`L${x} 270`);return{path:points.join(' '),x};}
