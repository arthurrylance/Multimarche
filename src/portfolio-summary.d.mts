import type {Market,Position} from './types';
export type PositionCosts=Record<string,{yes:number;no:number}>;
export type SettlementOutcome={side:'yes'|'no';payout:number;profit:number|null;percent:number|null};
export type PositionSummary={market:Market;yes:number;no:number;reservedYes:number;reservedNo:number;basis:number|null;value:number|null;unrealized:number|null;outcomes:SettlementOutcome[];payout:number;profit:number|null;percent:number|null};
export type PositionGroup={key:string;title:string;rows:PositionSummary[]};
export function positionSummaries(markets:Market[],positions:Position[],costs?:PositionCosts):PositionSummary[];
export function groupPositions(rows:PositionSummary[]):PositionGroup[];
export function positionTotals(rows:PositionSummary[]):{count:number;basis:number|null;payout:number;profit:number|null;percent:number|null};
