import type {BookLevel} from './orderbook.mjs';
export function bookQuote(args:{levels:BookLevel[];action:'buy'|'sell';amount:number;mode:'market'|'limit';price:number}):{limit:number;quantity:number;filled:number;remaining:number;cost:number;average:number;worst:number|null};
