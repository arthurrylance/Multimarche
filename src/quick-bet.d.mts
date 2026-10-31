import type {BookLevel} from './orderbook.mjs';
export function automaticPrice(levels:BookLevel[],action:'buy'|'sell',fallback?:number):number;
export function quantityForCredits(credits:string|number,price:number):number;
export function sellFraction(available:number,percent:number):number;
