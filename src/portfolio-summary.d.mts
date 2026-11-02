import type {Market,Position} from './types';
export type PositionCosts=Record<string,{yes:number;no:number}>;
export type PositionSummary={market:Market;yes:number;no:number;reservedYes:number;reservedNo:number;basis:number|null;value:number|null;profit:number|null;percent:number|null};
export type PositionGroup={key:string;title:string;rows:PositionSummary[]};
export function positionSummaries(markets:Market[],positions:Position[],costs?:PositionCosts):PositionSummary[];
export function groupPositions(rows:PositionSummary[]):PositionGroup[];
export function positionTotals(rows:PositionSummary[]):{count:number;basis:number|null;value:number|null;profit:number|null;percent:number|null};
