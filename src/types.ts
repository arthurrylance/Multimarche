export type Market = {id:string;creator_id:string;title:string;description:string;category:string;emoji:string;closes_at:string;created_at:string;status:'open'|'proposed'|'resolved';q_yes:number;q_no:number;liquidity:number;probability:number;volume:number;outcome:'yes'|'no'|'void'|null;resolved_at:string|null;paused:boolean;archived:boolean;admin_resolved:boolean;yes_rule:string;no_rule:string;required_verifications:number;state_changed_at:string;counter_enabled:boolean;counter_label:string;counter_value:number;counter_updated_at:string|null};
export type Profile = {id:string;username:string;nickname:string};
export type Position = {user_id:string;market_id:string;side:'yes'|'no';shares:number;net_cost:number};
export type Trade = {id:string;user_id:string;market_id:string;side:string;action:string;shares:number;total:number;probability:number;created_at:string};
export type Vote = {market_id:string;user_id:string;outcome:string;evidence:string;created_at:string};
export type Comment = {id:string;user_id:string;market_id:string;body:string;created_at:string};
