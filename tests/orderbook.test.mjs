import test from 'node:test';import assert from 'node:assert/strict';import {quoteOrder,marketLimit,maxShares} from '../src/orderbook.mjs';
test('book quotes use best prices, respect limits and expose partial liquidity',()=>{
 const levels=[{price:.7,size:10},{price:.5,size:20},{price:.6,size:30}];
 const q=quoteOrder(levels,40,.65,'buy');assert.equal(q.filled,40);assert.equal(q.cost,22);assert.equal(q.worst,.6);assert.equal(q.remaining,0);
 const partial=quoteOrder(levels,80,.65,'buy');assert.equal(partial.filled,50);assert.equal(partial.remaining,30);assert.equal(partial.cost,28);
 const sell=quoteOrder(levels,25,.6,'sell');assert.equal(sell.filled,25);assert.equal(sell.cost,16);assert.equal(sell.worst,.6);
});
test('empty liquidity does not invent executions or prices',()=>{
 assert.deepEqual(quoteOrder([],25,.8,'buy'),{filled:0,remaining:25,cost:0,average:0,worst:null});
 assert.equal(maxShares([],100),0);assert.equal(quoteOrder([{price:.8,size:10}],5,.7,'buy').filled,0);
});
test('market price protection rounds to valid ticks and bounds risk',()=>{
 assert.equal(marketLimit(.6,'buy'),.603);assert.equal(marketLimit(.6,'sell'),.597);assert.equal(marketLimit(.9999,'buy'),.9999);assert.equal(marketLimit(.0001,'sell'),.0001);
 for(const price of [.0123,.4567,.8765]){assert.ok(marketLimit(price,'buy')>=price);assert.ok(marketLimit(price,'sell')<=price);assert.equal(Number(marketLimit(price,'buy').toFixed(4)),marketLimit(price,'buy'));}
});
test('maximum quoted share count respects real depth and budget',()=>{
 const levels=[{price:.5,size:10},{price:.8,size:20}];assert.equal(maxShares(levels,9),15);assert.equal(maxShares(levels,100),30);
});
