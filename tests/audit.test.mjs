import test from 'node:test';import assert from 'node:assert/strict';import {createHash} from 'node:crypto';import {verifyLedger} from '../src/audit.mjs';
function chain(data){let prev='0'.repeat(64);return data.map((entry,i)=>{const payload=JSON.stringify({...entry,seq:i+1,previous_hash:prev}),hash=createHash('sha256').update(payload).digest('hex'),b={seq:i+1,previous_hash:prev,hash,payload};prev=hash;return b;});}
const genesis={kind:'genesis',total_supply:'1000',accounts:[{account:'treasury',balance:'1000'}]};
test('ledger replay conserves precise credits and tracks explicit issuance',async()=>{const blocks=chain([genesis,{kind:'transfer',from:'treasury',to:'user',amount:'0.000000000000000001'},{kind:'mint',to:'treasury',amount:'100',total_supply:'1100'}]);const result=await verifyLedger(blocks);assert.equal(result.height,3);assert.equal(result.supply,1100n*10n**80n);assert.equal(result.balances.get('user'),10n**62n);});
test('ledger rejects tampering, gaps and unfunded transfers even if rehashed',async()=>{
 const blocks=chain([genesis,{kind:'transfer',from:'treasury',to:'user',amount:'10'}]);const tampered=structuredClone(blocks);tampered[1].payload=tampered[1].payload.replace('10','20');await assert.rejects(()=>verifyLedger(tampered));
 await assert.rejects(()=>verifyLedger([blocks[1]]));
 await assert.rejects(()=>verifyLedger(chain([genesis,{kind:'transfer',from:'treasury',to:'user',amount:'1001'}])));
 await assert.rejects(()=>verifyLedger(chain([{...genesis,total_supply:'1001'}])));
});
