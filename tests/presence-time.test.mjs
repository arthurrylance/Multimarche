import test from 'node:test';import assert from 'node:assert/strict';import {lastBetLabel} from '../src/presence-time.mjs';
test('last bet labels distinguish recent, hourly, daily and absent bets',()=>{
 const now=Date.parse('2026-10-31T17:00:00Z');
 assert.equal(lastBetLabel(null,now),'No bets yet');assert.equal(lastBetLabel('invalid',now),'Last bet unavailable');
 assert.equal(lastBetLabel('2026-10-31T16:59:30Z',now),'Last bet just now');assert.equal(lastBetLabel('2026-10-31T16:59:00Z',now),'Last bet 1 minute ago');
 assert.equal(lastBetLabel('2026-10-31T16:30:00Z',now),'Last bet 30 minutes ago');assert.equal(lastBetLabel('2026-10-31T16:00:00Z',now),'Last bet 1 hour ago');
 assert.equal(lastBetLabel('2026-10-31T14:00:00Z',now),'Last bet 3 hours ago');assert.equal(lastBetLabel('2026-10-30T17:00:00Z',now),'Last bet 1 day ago');
 assert.equal(lastBetLabel('2026-10-31T17:00:05Z',now),'Last bet just now');
});
