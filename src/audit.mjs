import {sha256,toUtf8Bytes} from 'ethers';
const units=value=>{const s=String(value);if(!/^\d+(\.\d+)?$/.test(s))throw new Error('Invalid credit amount');const [whole,fraction='']=s.split('.');if(fraction.length>80)throw new Error('Unsupported credit precision');return BigInt(whole+fraction.padEnd(80,'0'));};
export function verifyLedger(blocks){
 let previous='0'.repeat(64),sequence=1,supply=0n;const balances=new Map();
 for(const block of blocks){
  const data=JSON.parse(block.payload);
  if(Number(block.seq)!==sequence||block.previous_hash!==previous||data.previous_hash!==previous||Number(data.seq)!==sequence||sha256(toUtf8Bytes(block.payload)).slice(2)!==block.hash)throw new Error(`Invalid ledger block ${sequence}`);
  if(sequence===1){
   if(data.kind!=='genesis')throw new Error('Missing genesis');supply=units(data.total_supply);
   for(const account of data.accounts){if(balances.has(account.account))throw new Error('Duplicate genesis account');balances.set(account.account,units(account.balance));}
  }else if(data.kind==='transfer'){
   const amount=units(data.amount),from=balances.get(data.from)??0n;if(amount<=0n||from<amount||data.from===data.to)throw new Error('Invalid funded transfer');balances.set(data.from,from-amount);balances.set(data.to,(balances.get(data.to)??0n)+amount);
  }else if(data.kind==='mint'){
   const amount=units(data.amount);if(amount<=0n)throw new Error('Invalid issuance');supply+=amount;if(supply!==units(data.total_supply))throw new Error('Issuance does not reconcile');balances.set(data.to,(balances.get(data.to)??0n)+amount);
  }else throw new Error('Unknown transaction kind');
  if([...balances.values()].reduce((a,b)=>a+b,0n)!==supply)throw new Error(`Supply mismatch at block ${sequence}`);
  previous=block.hash;sequence++;
 }
 return {height:sequence-1,head:previous,supply,balances};
}
