import test from 'node:test';import assert from 'node:assert/strict';
import {summarizeBets,timeRemaining} from '../src/bet-summary.mjs';
test('bet summary combines both sides and accounts for previous sales in net profit',()=>{
 const markets=[{id:'open',status:'open',probability:.7,closes_at:'2026-10-31T15:40:00Z'},{id:'done',status:'resolved'}];
 const positions=[{market_id:'open',side:'yes',shares:'40',net_cost:'15'},{market_id:'open',side:'no',shares:'10',net_cost:'8'},{market_id:'done',side:'yes',shares:99,net_cost:1}];
 const [bet]=summarizeBets(markets,positions);assert.equal(bet.netCost,23);assert.equal(bet.value,31);assert.equal(bet.profit,8);assert.equal(bet.ifYes,17);assert.equal(bet.ifNo,-13);assert.equal(summarizeBets(markets,positions).length,1);
 const [sold]=summarizeBets([markets[0]],[{market_id:'open',side:'yes',shares:5,net_cost:-2}]);assert.equal(sold.ifYes,7);assert.equal(sold.ifNo,2);
});
test('countdown changes to awaiting result or confirmation and excludes fully sold markets',()=>{
 const market={id:'a',status:'open',closes_at:'2026-10-31T15:40:00Z'};
 assert.equal(timeRemaining(market,Date.parse('2026-10-31T15:00:00Z')),'40m 0s left');
 assert.equal(timeRemaining(market,Date.parse(market.closes_at)),'Awaiting result');
 assert.equal(timeRemaining({...market,status:'proposed'},0),'Awaiting confirmation');
 assert.equal(timeRemaining({...market,paused:true},Date.parse('2026-10-31T15:39:59Z')),'Paused · 0m 1s left');
 assert.deepEqual(summarizeBets([market],[{market_id:'a',side:'yes',shares:0,net_cost:-10}]),[]);
});
