import test from 'node:test';
import assert from 'node:assert/strict';
import {bookQuote} from '../src/trading-quote.mjs';
test('market buy walks depth and keeps its worst-case reservation within the entered budget',()=>{
 const q=bookQuote({levels:[{price:.4,size:10},{price:.6,size:100}],action:'buy',amount:25,mode:'market',price:.5});
 assert.equal(q.limit,.603);assert.ok(q.quantity*.603<=25);assert.ok(q.cost<=25);assert.ok(q.filled>10);assert.equal(q.remaining,0);
});
test('market sell prices against bids and exposes partial fills without inventing liquidity',()=>{
 const q=bookQuote({levels:[{price:.7,size:5},{price:.6,size:3}],action:'sell',amount:20,mode:'market',price:.5});
 assert.equal(q.limit,.597);assert.equal(q.filled,8);assert.equal(q.remaining,12);assert.ok(Math.abs(q.cost-5.3)<1e-8);
 const empty=bookQuote({levels:[],action:'buy',amount:25,mode:'market',price:.5});assert.equal(empty.filled,0);
});
test('limit quotes respect the entered price and integer budget arithmetic',()=>{
 const q=bookQuote({levels:[{price:.6,size:100}],action:'buy',amount:25,mode:'limit',price:.5});assert.equal(q.quantity,50);assert.equal(q.filled,0);assert.equal(q.remaining,50);
 for(const amount of [.01,.03,1,25.99,999.99])for(const price of [.0001,.3333,.9999]){
  const value=bookQuote({levels:[],action:'buy',amount,mode:'limit',price});assert.ok(value.quantity*price<=amount+1e-9);
 }
 for(const price of [0,NaN,1])assert.equal(bookQuote({levels:[],action:'buy',amount:1,mode:'limit',price}).quantity,0);
});
