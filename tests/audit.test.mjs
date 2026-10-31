import test from 'node:test';import assert from 'node:assert/strict';import {sha256,toUtf8Bytes} from 'ethers';import {verifyLedger} from '../src/audit.mjs';
function chain(data){let prev='0'.repeat(64);return data.map((entry,i)=>{const payload=JSON.stringify({...entry,seq:i+1,previous_hash:prev}),hash=sha256(toUtf8Bytes(payload)).slice(2),b={seq:i+1,previous_hash:prev,hash,payload};prev=hash;return b;});}
const genesis={kind:'genesis',total_supply:'1000',accounts:[{account:'treasury',balance:'1000'}]};
test('ledger replay conserves precise credits and tracks explicit issuance',()=>{const blocks=chain([genesis,{kind:'transfer',from:'treasury',to:'user',amount:'0.000000000000000001'},{kind:'mint',to:'treasury',amount:'100',total_supply:'1100'}]);const result=verifyLedger(blocks);assert.equal(result.height,3);assert.equal(result.supply,1100n*10n**80n);assert.equal(result.balances.get('user'),10n**62n);});
test('ledger rejects tampering, gaps and unfunded transfers even if rehashed',()=>{
 const blocks=chain([genesis,{kind:'transfer',from:'treasury',to:'user',amount:'10'}]);const tampered=structuredClone(blocks);tampered[1].payload=tampered[1].payload.replace('10','20');assert.throws(()=>verifyLedger(tampered));
 assert.throws(()=>verifyLedger([blocks[1]]));
 assert.throws(()=>verifyLedger(chain([genesis,{kind:'transfer',from:'treasury',to:'user',amount:'1001'}])));
 assert.throws(()=>verifyLedger(chain([{...genesis,total_supply:'1001'}])));
});
