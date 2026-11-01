export type SnakeState={body:number[];direction:number;apple:number;seed:number;score:number;steps:number;over:boolean};
export type SnakeSnapshot={session:{id:string;state:SnakeState;awarded:number;status:string}|null;earned:number;remaining:number;daily_limit:number;tick_ms:number};
export const snakeSize:number,snakeTick:number;
export function snakeApple(body:number[],seed:number):{apple:number;seed:number};
export function snakeInitial(seed?:number):SnakeState;
export function snakeMove(state:SnakeState,input:number):SnakeState;
export class SnakeTransport {
 constructor(rpc:(name:string,args?:Record<string,unknown>)=>PromiseLike<{data:any;error:any}>,changed:(data:SnakeSnapshot)=>void,failed:(message:string)=>void,credited:()=>void);
 data:SnakeSnapshot|null;state:SnakeState;error:boolean;queue:number[];
 load():Promise<void>;start(restart?:boolean):Promise<boolean>;move(direction:number):boolean;flush():Promise<void>;retry():Promise<void>;dispose():void;
}
