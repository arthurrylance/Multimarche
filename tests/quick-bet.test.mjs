import test from 'node:test';import assert from 'node:assert/strict';
import {automaticPrice,quantityForCredits,sellFraction} from '../src/quick-bet.mjs';
import {avatarNames,avatarPath} from '../src/avatar.mjs';
import {readFileSync} from 'node:fs';
test('quick betting selects real best prices and falls back to the current mark or 50/50',()=>{
 const levels=[{price:.7,size:10},{price:.6,size:20},{price:.1,size:0}];assert.equal(automaticPrice(levels,'buy'),.6);assert.equal(automaticPrice(levels,'sell'),.7);assert.equal(automaticPrice([],'buy'),.5);assert.equal(automaticPrice([],'buy',.72),.72);assert.equal(automaticPrice([],'sell',1),.9999);
});
test('credit budgets round down to exact share ticks without overspending at any price',()=>{
 for(let ticks=1;ticks<=9999;ticks+=13){for(const cents of [1,123,2500,99999]){const price=ticks/10000,qty=quantityForCredits(cents/100,price),shareTicks=Math.round(qty*10000);assert.ok(BigInt(shareTicks)*BigInt(ticks)<=BigInt(cents)*1000000n);if(qty>0)assert.ok(BigInt(shareTicks+1)*BigInt(ticks)>BigInt(cents)*1000000n);}}
 assert.equal(quantityForCredits(25,.5),50);assert.equal(quantityForCredits(10,.65),15.3846);assert.equal(quantityForCredits(-1,.5),0);assert.equal(quantityForCredits('1.234',.5),0);assert.equal(quantityForCredits(Infinity,.5),0);
});
test('fractional cash out never pledges reserved shares or rounds above holdings',()=>{
 assert.equal(sellFraction(2,50),1);assert.equal(sellFraction(.0003,50),.0001);assert.equal(sellFraction(.0003,100),.0003);assert.equal(sellFraction(0,100),0);assert.equal(sellFraction(10,101),0);
});
test('account pictures are stable across reloads and use all eight supplied assets',()=>{
 const selected=new Set();for(let i=0;i<256;i++){const id=`00000000-0000-4000-8000-${String(i).padStart(12,'0')}`;assert.equal(avatarPath(id),avatarPath(id.toUpperCase()));selected.add(avatarPath(id));}assert.equal(selected.size,8);
 for(const name of avatarNames){const file=readFileSync(new URL(`../public/avatars/${name}.png`,import.meta.url));assert.equal(file.subarray(1,4).toString(),'PNG');assert.ok(file.length>1000);}
});
