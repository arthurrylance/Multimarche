import test from 'node:test';import assert from 'node:assert/strict';
import {marketNotifications,requiresTradeConfirmation,recordEscape} from '../src/interactions.mjs';
test('large bets require confirmation by absolute cost or relative cash',()=>{
 assert.equal(requiresTradeConfirmation(100,1000),true);assert.equal(requiresTradeConfirmation(99,1000),false);
 assert.equal(requiresTradeConfirmation(25,100),true);assert.equal(requiresTradeConfirmation(24,100),false);
 assert.equal(requiresTradeConfirmation(0,0),false);
});
test('Escape shortcut requires three presses within a short window',()=>{
 let taps=[];taps=recordEscape(taps,1000);taps=recordEscape(taps,1500);assert.equal(taps.length,2);taps=recordEscape(taps,2200);assert.equal(taps.length,3);
 assert.equal(recordEscape(taps,4000).length,1);
});
test('notifications distinguish deadlines, proposals and outcomes with stable read keys',()=>{
 const base={id:'m',title:'Event?',closes_at:'2026-10-31T10:00:00Z',state_changed_at:'2026-10-31T10:01:00Z',required_verifications:3,status:'open'};
 assert.equal(marketNotifications([base],[],'a',Date.parse('2026-10-31T09:00:00Z')).length,0);
 const ended=marketNotifications([base],[],'a',Date.parse('2026-10-31T11:00:00Z'))[0];assert.equal(ended.kind,'ended');
 const votes=[{market_id:'m',user_id:'a',outcome:'yes'},{market_id:'m',user_id:'b',outcome:'yes'}];
 const proposed=marketNotifications([{...base,status:'proposed',outcome:'yes'}],votes,'a')[0];assert.equal(proposed.count,2);assert.equal(proposed.required,3);assert.equal(proposed.hasVoted,true);assert.notEqual(proposed.key,ended.key);
 const resolved=marketNotifications([{...base,status:'resolved',outcome:'yes',resolved_at:'2026-10-31T10:05:00Z'}],votes,'c')[0];assert.equal(resolved.kind,'resolved');assert.notEqual(resolved.key,proposed.key);
 assert.equal(marketNotifications([{...base,archived:true}],votes,'a').length,0);
});
