import type {Market,Vote} from './types';
export function requiresTradeConfirmation(cost:number,balance:number):boolean;
export function recordEscape(previous:number[],now:number):number[];
export const EMERGENCY_URL:string;
export function shouldRedirectForEmergency(signal:{version:number|string;triggered_at:string|null},lastSeen:number|null,now?:number):boolean;
export type MarketNotification={key:string;kind:string;market:Market;count:number;required:number;hasVoted:boolean;ownOutcome:string|null;counts:{yes:number;no:number;void:number};timestamp:string};
export function marketNotifications(markets:Market[],votes:Vote[],userId:string,now?:number):MarketNotification[];
