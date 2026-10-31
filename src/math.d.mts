import type {Market} from './types';
export function cost(y:number,n:number,b?:number):number;
export function quote(m:Market,side:string,action:string,shares:number):number;
export function sharesForBudget(m:Market,side:string,budget:number):number;
