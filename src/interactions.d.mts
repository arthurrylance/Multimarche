import type {Market,Vote} from './types';
export function requiresTradeConfirmation(cost:number,balance:number):boolean;
export function recordEscape(previous:number[],now:number):number[];
export type MarketNotification={key:string;kind:string;market:Market;count:number;required:number;hasVoted:boolean;timestamp:string};
export function marketNotifications(markets:Market[],votes:Vote[],userId:string,now?:number):MarketNotification[];
