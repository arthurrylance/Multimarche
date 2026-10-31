export type BookLevel={price:number;size:number};
export function quoteOrder(levels:BookLevel[],quantity:number,limit:number,action:string):{filled:number;remaining:number;cost:number;average:number;worst:number|null};
export function marketLimit(worst:number|null,action:string):number;
export function maxShares(levels:BookLevel[],budget:number):number;
