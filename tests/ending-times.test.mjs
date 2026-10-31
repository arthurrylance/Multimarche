import test from 'node:test';import assert from 'node:assert/strict';import {SCHOOL_ENDINGS,schoolDateTime,schoolDate,suggestedSchoolDate,resolveEnding} from '../src/ending-times.mjs';
test('school preset labels and times exactly match the supplied timetable',()=>{
 assert.deepEqual(SCHOOL_ENDINGS.map(x=>[x.label,x.time]),[['P1','09:00'],['P2','09:50'],['P3','10:30'],['Recess','10:50'],['P4','11:30'],['P5','12:15'],['P6','13:00'],['Lunch','13:35'],['P8','14:20'],['P9','15:05'],['School day','15:50']]);
});
test('fixed school times use Zurich winter and summer offsets independently of device time',()=>{
 assert.equal(schoolDateTime('2026-11-02T09:00').toISOString(),'2026-11-02T08:00:00.000Z');
 assert.equal(schoolDateTime('2026-06-01T09:00').toISOString(),'2026-06-01T07:00:00.000Z');
 assert.equal(schoolDate(Date.parse('2026-11-01T23:30:00Z')),'2026-11-02');
});
test('school dates stay on today while periods remain and advance across weekends',()=>{
 assert.equal(suggestedSchoolDate(Date.parse('2026-11-02T08:00Z')),'2026-11-02');
 assert.equal(suggestedSchoolDate(Date.parse('2026-11-02T14:50Z')),'2026-11-03');
 assert.equal(suggestedSchoolDate(Date.parse('2026-10-31T12:00Z')),'2026-11-02');
 assert.equal(suggestedSchoolDate(Date.parse('2026-10-30T16:00Z')),'2026-11-02');
});
test('intervals start at creation time and tomorrow respects calendar DST changes',()=>{
 const now=Date.parse('2026-10-24T10:00Z');
 assert.equal(resolveEnding({kind:'interval',minutes:30},now).toISOString(),'2026-10-24T10:30:00.000Z');
 assert.equal(resolveEnding({kind:'tomorrow'},now).toISOString(),'2026-10-25T11:00:00.000Z');
 assert.equal(resolveEnding({kind:'tomorrow'},Date.parse('2026-03-28T11:00Z')).toISOString(),'2026-03-29T10:00:00.000Z');
});
test('expired periods, invalid intervals, malformed dates and skipped DST times are rejected',()=>{
 assert.throws(()=>resolveEnding({kind:'school',local:'2026-11-02T09:00'},Date.parse('2026-11-02T08:00Z')),/future/);
 assert.throws(()=>resolveEnding({kind:'interval',minutes:0}),/interval/);
 assert.throws(()=>schoolDateTime('2026-02-31T09:00'),/valid/);
 assert.throws(()=>schoolDateTime('2026-03-29T02:30'),/valid/);
 assert.throws(()=>schoolDateTime(''),/Choose/);
});
