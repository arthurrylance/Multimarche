export const wheel:number[];export const redNumbers:Set<number>;export const multipliers:number[];
export function cardFace(card:number|null):{rank:string;suit:string;red:boolean};
export function wheelRotation(number:number):number;export function wheelWedge(index:number):string;
export function plinkoPath(bits:number[]):{path:string;x:number};

export const plinkoDuration:number;
export function plinkoPoint(bits:number[],progress:number):{x:number;y:number};
