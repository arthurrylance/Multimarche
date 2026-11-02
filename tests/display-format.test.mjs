import test from 'node:test';
import assert from 'node:assert/strict';
import {formatShares,formatDate,formatDateTime,dateInputDisplay,parseDateInput} from '../src/display-format.mjs';
import {schoolDateTime} from '../src/ending-times.mjs';
test('share readouts always use two decimal places without changing source quantities',()=>{
 for(const [value,expected] of [[0,'0.00'],[1,'1.00'],[1.2345,'1.23'],[1.2356,'1.24'],[.0001,'0.00'],[1234.5678,'1,234.57']])assert.equal(formatShares(value),expected);
 const held=1.2345;formatShares(held);assert.equal(held,1.2345);
});
test('calendar dates are padded dd/mm/yyyy with Zurich timestamps across DST and midnight',()=>{
 assert.equal(formatDate('2026-01-03T12:00:00Z'),'03/01/2026');
 assert.equal(formatDateTime('2026-11-01T23:30:00Z'),'02/11/2026 00:30');
 assert.equal(formatDateTime('2026-06-01T07:00:00Z'),'01/06/2026 09:00');
 assert.equal(formatDateTime('2026-11-02T08:00:00Z'),'02/11/2026 09:00');
 assert.equal(formatDate('invalid'),'—');
});
test('dd/mm/yyyy form values round-trip to existing ISO API values and reject impossible dates',()=>{
 for(const value of ['2026-01-03','2028-02-29','2026-12-31'])assert.equal(parseDateInput(dateInputDisplay(value)),value);
 for(const value of ['31/02/2026','29/02/2027','00/11/2026','11/13/2026','1/2/2026','2026-11-02',''])assert.equal(parseDateInput(value),null);
 assert.equal(schoolDateTime(`${parseDateInput('02/11/2026')}T09:00`).toISOString(),'2026-11-02T08:00:00.000Z');
 assert.throws(()=>schoolDateTime(`${parseDateInput('29/03/2026')}T02:30`),/valid/);
});
