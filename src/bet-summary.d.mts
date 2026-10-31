import type {Market,Position} from './types';
export type BetSummary={market:Market;yes:number;no:number;netCost:number;value:number;profit:number;ifYes:number;ifNo:number};
export function summarizeBets(markets:Market[],positions:Position[]):BetSummary[];
export function timeRemaining(market:Market,now?:number):string;
