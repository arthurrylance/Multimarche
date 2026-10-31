export type EndingSelection={kind:'interval';minutes:number}|{kind:'tomorrow'}|{kind:'school';local:string};
export const SCHOOL_ZONE:string;
export const SCHOOL_ENDINGS:{label:string;name:string;time:string}[];
export function schoolDate(now?:number):string;
export function schoolDateTime(local:string):Date;
export function suggestedSchoolDate(now?:number):string;
export function resolveEnding(value:EndingSelection,now?:number):Date;
