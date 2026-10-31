import test from 'node:test';import assert from 'node:assert/strict';
import {groupOptions,marketListings} from '../src/market-groups.mjs';
const base={status:'open',created_at:'2026-10-31T10:00:00Z',closes_at:'2026-10-31T12:00:00Z',volume:0};
const markets=[{...base,id:'a',title:'Physics · Etcetera',group_id:'g',group_title:'Physics',option_label:'Etcetera',group_position:0,volume:10,probability:.8},{...base,id:'b',title:'Physics · Homework',group_id:'g',group_title:'Physics',option_label:'Homework',group_position:1,volume:20,probability:.7},{...base,id:'single',title:'Another bet',volume:100}];
test('options form one listing, with aggregate volume and unchanged independent probabilities',()=>{
 const input=Object.freeze(markets.map(Object.freeze)),list=marketListings(input);assert.equal(list.length,2);const group=list.find(g=>g.groupId);assert.equal(group.title,'Physics');assert.equal(group.volume,30);assert.deepEqual(group.markets.map(m=>m.probability),[.8,.7]);assert.equal(input.length,3);
});
test('starring an option pins its group; title and option searches retain sibling context',()=>{
 const list=marketListings(markets,['b']);assert.equal(list[0].groupId,'g');assert.equal(marketListings(markets,[],'Trending','Homework')[0].openId,'b');assert.equal(marketListings(markets,[],'Trending','Physics')[0].markets.length,2);assert.equal(marketListings(markets,[],'Trending','not found').length,0);
});
test('mixed-result groups remain together, while fully hidden or archived groups disappear',()=>{
 const mixed=[{...markets[0],status:'resolved',outcome:'yes'},markets[1]];assert.equal(marketListings(mixed)[0].markets.length,2);assert.equal(marketListings(mixed,[],'Resolved')[0].markets.length,2);assert.equal(marketListings(mixed,[],'Resolved')[0].openId,'a');assert.equal(marketListings(mixed.map(m=>({...m,status:'resolved'}))).length,0);assert.equal(marketListings(mixed.map(m=>({...m,history_deleted_at:'2026-10-31'}))).length,0);assert.equal(marketListings(mixed.map(m=>({...m,archived:true}))).length,0);
});
test('sibling navigation follows option order and excludes deleted history',()=>{
 const result=groupOptions([markets[1],{...markets[0],history_deleted_at:'2026-10-31'},markets[2]],'g');assert.deepEqual(result.map(m=>m.id),['b']);assert.deepEqual(groupOptions([markets[1],markets[0]],'g').map(m=>m.id),['a','b']);
});
