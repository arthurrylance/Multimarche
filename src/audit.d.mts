export type AuditBlock={seq:number;previous_hash:string;hash:string;payload:string;created_at:string};
export function verifyLedger(blocks:AuditBlock[]):Promise<{height:number;head:string;supply:bigint;balances:Map<string,bigint>}>;
