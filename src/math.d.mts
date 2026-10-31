import type {Market} from './types';
export function cost(y:number,n:number,b?:number):number;
export function quote(m:Market,side:string,action:string,shares:number):number;
export function sharesForBudget(m:Market,side:string,budget:number):number;
export function netPreview(held:number,netCost:number,side:string,quantity:number,total:number):{side:string;shares:number;cash:number;yes:number;no:number};
