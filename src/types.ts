export type Market = {id:string;creator_id:string;title:string;description:string;category:string;emoji:string;closes_at:string;created_at:string;status:'open'|'proposed'|'resolved';q_yes:number;q_no:number;liquidity:number;probability:number;volume:number;outcome:'yes'|'no'|'void'|null;resolved_at:string|null;paused:boolean;archived:boolean;admin_resolved:boolean;yes_rule:string;no_rule:string;required_verifications:number;state_changed_at:string;counter_enabled:boolean;counter_label:string;counter_value:number;counter_updated_at:string|null;history_deleted_at?:string|null;execution_model?:'amm'|'clob';resolution_disputed?:boolean;price_available?:boolean;last_trade_price?:number|null;book_version?:number};
export type Profile = {id:string;avatar_color?:string|null;username:string;nickname:string;active?:boolean;frozen_until?:string|null};
export type Position = {user_id:string;market_id:string;side:'yes'|'no';shares:number;net_cost:number;reserved_shares?:number};
export type Trade = {id:string;user_id:string;market_id:string;side:string;action:string;shares:number;total:number;probability:number;created_at:string;order_id?:string|null;fill_id?:string|null};
export type Vote = {market_id:string;user_id:string;outcome:string;evidence:string;created_at:string};
export type Comment = {id:string;user_id:string;market_id:string;body:string;created_at:string};

export type AdminMember=Profile&{balance:number;reserved_balance?:number;admin:boolean;active:boolean;deleted_at:string|null;auth_deleted_at:string|null;created_at:string;equity:number;open_bets:number;spent:number;sales:number;payouts:number};

export type BookOrder={id:string;market_id:string;side:'yes'|'no';action:'buy'|'sell';price:number;quantity:number;filled:number;remaining:number;status:string;tif:string;expires_at:string;created_at:string};
