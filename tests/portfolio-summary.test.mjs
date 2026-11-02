import test from 'node:test';import assert from 'node:assert/strict';
import {positionSummaries,positionTotals,groupPositions} from '../src/portfolio-summary.mjs';
const market=(id,extra={})=>({id,title:id,status:'open',probability:.7,closes_at:'2099-11-04',...extra});
const held=(id,side,shares,net_cost=0,reserved_shares=0)=>({market_id:id,side,shares,net_cost,reserved_shares});
test('portfolio uses remaining purchase basis after sales, combines both sides, and computes weighted return',()=>{
 const rows=positionSummaries([market('a'),market('b'),market('settled',{status:'resolved'})],[held('a','yes',10,-2,3),held('a','no',5,2),held('b','yes',20,3),held('settled','no',100,80)],{a:{yes:4,no:2},b:{yes:10,no:0}});
 assert.equal(rows[0].basis,6);assert.deepEqual(rows[0].outcomes.map(o=>[o.side,o.payout,o.profit]),[['yes',10,4],['no',5,-1]]);assert.equal(rows[0].payout,10);assert.equal(rows[0].profit,4);assert.ok(Math.abs(rows[0].percent-66.6666666667)<1e-7);assert.equal(rows[0].reservedYes,3);
 const total=positionTotals(rows);assert.equal(total.count,2);assert.equal(total.basis,16);assert.equal(total.payout,30);assert.equal(total.profit,14);assert.equal(total.percent,87.5);
 assert.equal(rows[2].market.status,'resolved');assert.equal(rows[2].payout,100);
});
test('settlement payouts need no current book price; missing costs and zero basis do not invent profit or return',()=>{
 const rows=positionSummaries([market('a'),market('b',{price_available:false})],[held('a','yes',10,-2),held('b','no',10,5)],{b:{yes:0,no:5}});
 assert.equal(rows[0].basis,null);assert.equal(rows[0].profit,null);assert.equal(rows[1].outcomes[0].payout,10);assert.equal(rows[1].outcomes[0].profit,5);assert.equal(rows[1].outcomes[0].percent,100);assert.equal(positionTotals(rows).profit,null);
 const [free]=positionSummaries([market('a')],[held('a','yes',1)],{a:{yes:0,no:0}});assert.equal(free.percent,null);assert.equal(free.profit,1);
 assert.deepEqual(positionTotals([]),{count:0,basis:0,payout:0,profit:0,percent:null});
});
test('four independent held options share a card without losing sides, order, or the solo market',()=>{
 const markets=[market('d',{group_id:'g',group_title:'Weekly words',group_position:3}),market('b',{group_id:'g',group_title:'Weekly words',group_position:1}),market('a',{group_id:'g',group_title:'Weekly words',group_position:0}),market('c',{group_id:'g',group_title:'Weekly words',group_position:2}),market('solo')];
 const rows=positionSummaries(markets,markets.map(m=>held(m.id,'no',10)));
 const groups=groupPositions(rows);assert.equal(groups.length,2);assert.equal(groups[0].title,'Weekly words');assert.deepEqual(groups[0].rows.map(r=>r.market.id),['a','b','c','d']);assert.ok(groups[0].rows.every(r=>r.no===10&&r.yes===0));
 assert.equal(positionSummaries(markets,[held('solo','yes',0),held('missing','no',10)]).length,0);
});

test('winning No payout and return follow owned shares and remaining cost regardless of price movement',()=>{
 const positions=[held('a','no','217.35',-20)],costs={a:{yes:0,no:51.37}};
 const [low]=positionSummaries([market('a',{probability:.01})],positions,costs),[high]=positionSummaries([market('a',{probability:.99})],positions,costs);
 assert.deepEqual(low.outcomes,high.outcomes);assert.equal(low.outcomes[0].side,'no');assert.equal(low.outcomes[0].payout,217.35);assert.ok(Math.abs(low.outcomes[0].profit-165.98)<1e-8);assert.ok(Math.abs(low.outcomes[0].percent-165.98/51.37*100)<1e-8);
});
