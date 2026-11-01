const digest=async text=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),byte=>byte.toString(16).padStart(2,'0')).join('');
const units=value=>{const s=String(value);if(!/^\d+(\.\d+)?$/.test(s))throw new Error('Invalid credit amount');const [whole,fraction='']=s.split('.');if(fraction.length>80)throw new Error('Unsupported credit precision');return BigInt(whole+fraction.padEnd(80,'0'));};
export async function verifyLedger(blocks){
 let previous='0'.repeat(64),sequence=1,supply=0n;const balances=new Map(),debts=new Map();
 for(const block of blocks){
  const data=JSON.parse(block.payload);
  if(Number(block.seq)!==sequence||block.previous_hash!==previous||data.previous_hash!==previous||Number(data.seq)!==sequence||(await digest(block.payload))!==block.hash)throw new Error(`Invalid ledger block ${sequence}`);
  if(sequence===1){
   if(data.kind!=='genesis')throw new Error('Missing genesis');supply=units(data.total_supply);
   for(const account of data.accounts){if(balances.has(account.account))throw new Error('Duplicate genesis account');balances.set(account.account,units(account.balance));}
  }else if(data.kind==='transfer'){
   const amount=units(data.amount),from=balances.get(data.from)??0n,debt=debts.get(data.from);
   const repayment=data.reason==='Leverage repayment'&&debt?.creditor===data.to&&debt.amount>=amount;
   if(amount<=0n||data.from===data.to||(from<amount&&!repayment)||(data.reason==='Leverage repayment'&&!repayment))throw new Error('Invalid funded transfer');
   if(data.reason==='Leverage borrowing'){
    if((debts.get(data.to)?.amount??0n)>0n)throw new Error('Multiple active loans');
    debts.set(data.to,{creditor:data.from,amount});
   }
   if(repayment)debts.set(data.from,{creditor:debt.creditor,amount:debt.amount-amount});
   balances.set(data.from,from-amount);balances.set(data.to,(balances.get(data.to)??0n)+amount);
  }else if(data.kind==='mint'){
   const amount=units(data.amount);if(amount<=0n)throw new Error('Invalid issuance');supply+=amount;if(supply!==units(data.total_supply))throw new Error('Issuance does not reconcile');balances.set(data.to,(balances.get(data.to)??0n)+amount);
  }else throw new Error('Unknown transaction kind');
  if([...balances.values()].reduce((a,b)=>a+b,0n)!==supply)throw new Error(`Supply mismatch at block ${sequence}`);
  previous=block.hash;sequence++;
 }
 return {height:sequence-1,head:previous,supply,balances};
}
