import type {Market} from './types';
export type MarketListing={key:string;groupId:string|null;title:string;markets:Market[];openId:string;watched:boolean;volume:number;createdAt:number;closesAt:number};
export function groupOptions(markets:Market[],groupId:string):Market[];
export function marketListings(markets:Market[],watched?:string[],sort?:string,search?:string,now?:number):MarketListing[];
