import type {Market} from './types';import type {BookLevel} from './orderbook.mjs';
export type OutcomePreview={return:number|null;profit:number|null};
export type PositionProjection={side:string;shares:number;basis:number;change:string;cash:number;availableCash:number;realised:number;reserved:number;pending:number;matched:number;planned:number;failed:boolean;debt:number;yes:OutcomePreview;no:OutcomePreview};
export function positionChange(held:number,next:number):string;
export function currentPosition(args:{market:Market;held:number;basis:number;debt?:number;bids?:BookLevel[]}):{side:string;shares:number;basis:number;debt:number;now:OutcomePreview;yes:OutcomePreview;no:OutcomePreview;liquidShares:number;liquidReturn:number};
export function projectPosition(args:{market:Market;held:number;basis:number;side:string;quantity:number;limit?:number;levels?:BookLevel[];tif?:string;debt?:number;draw?:number;releasedReserve?:number}):PositionProjection;
