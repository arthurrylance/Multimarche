export const snakeSize=20, snakeTick=140;
export function snakeApple(body,previousSeed){const seed=previousSeed*48271%2147483647;for(let i=0;i<400;i++){const apple=(seed%400+i)%400;if(!body.includes(apple))return{apple,seed};}return{apple:-1,seed};}
export function snakeInitial(seed=17){const body=[210,209,208];return{body,direction:1,...snakeApple(body,seed),score:0,steps:0,over:false};}
export function snakeMove(state,input){
 if(!Number.isInteger(input)||input<0||input>3||state.over)throw Error('Invalid Snake move');
 const direction=(input+2)%4===state.direction?state.direction:input,head=state.body[0],next=head+[-20,1,20,-1][direction],steps=state.steps+1;
 if(next<0||next>=400||(direction===1&&head%20===19)||(direction===3&&head%20===0))return{...state,direction,steps,over:true};
 const grow=next===state.apple,tail=grow?state.body:state.body.slice(0,-1);
 if(tail.includes(next))return{...state,direction,steps,over:true};
 const body=[next,...tail];return{body,direction,...(grow?snakeApple(body,state.seed):{apple:state.apple,seed:state.seed}),score:state.score+(grow?1:0),steps,over:body.length>=400};
}
// Send direction batches, not client-reported scores. Uncertain requests retain their nonce.
export class SnakeTransport {
 constructor(rpc,changed,failed,credited){this.rpc=rpc;this.changed=changed;this.failed=failed;this.credited=credited;this.queue=[];this.pending=null;this.flight=null;this.data=null;this.state=snakeInitial();this.error=false;this.disposed=false;this.startRequest=null;}
 publish(){this.changed({...this.data,session:this.data?.session?{...this.data.session,state:this.state}:null});}
 async load(){const{data,error}=await this.rpc('snake_state');if(error)throw error;this.data=data;this.state=data.session?.state??snakeInitial();this.queue=[];this.pending=null;this.error=false;this.publish();}
 async start(restart=false){
  do{await this.flush();if(this.error)return false;}while(this.flight||this.pending||this.queue.length);
  if(!this.startRequest||this.startRequest.p_restart!==restart)this.startRequest={p_restart:restart,p_request:crypto.randomUUID()};
  const{data,error}=await this.rpc('snake_start',this.startRequest);if(error)throw error;
  this.startRequest=null;this.data=data;this.state=data.session.state;this.queue=[];this.publish();return true;
 }
 move(direction){if(!this.data?.session||this.state.over||this.error||this.queue.length>=32)return false;const score=this.state.score;this.state=snakeMove(this.state,direction);this.queue.push(direction);this.publish();if(this.queue.length>=8||this.state.score!==score||this.state.over)void this.flush();return true;}
 async flush(){
  if(this.flight)return this.flight;if(this.error||(!this.pending&&!this.queue.length))return;
  this.pending??={p_session:this.data.session.id,p_step:this.data.session.state.steps,p_moves:this.queue.splice(0,40),p_request:crypto.randomUUID()};
  const payload=this.pending;
  this.flight=(async()=>{try{
   const{data,error}=await this.rpc('snake_step',payload);if(error)throw error;
   const previous=this.data.earned;this.data=data;this.pending=null;
   this.state=this.queue.reduce((state,dir)=>snakeMove(state,dir),data.session.state);this.publish();if(data.earned!==previous)this.credited();
  }catch(e){this.error=true;this.failed(e.message||'Could not save this game.');}finally{this.flight=null;if(!this.error&&this.queue.length&&(this.disposed||this.queue.length>=8||this.state.score>this.data.session.state.score||this.state.over))void this.flush();}})();
  return this.flight;
 }
 async retry(){this.error=false;await this.flush();}
 dispose(){this.disposed=true;void this.flush();}
}
