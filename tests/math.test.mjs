import test from 'node:test';
import assert from 'node:assert/strict';
import {cost,quote,sharesForBudget} from '../src/math.mjs';
const market={q_yes:0,q_no:0,liquidity:100};
test('initial market is symmetric and buying moves the marginal price',()=>{
 assert.equal(quote(market,'yes','buy',100),quote(market,'no','buy',100));
 const total=quote(market,'yes','buy',100);
 assert.ok(total>50&&total<100);
 assert.ok(1/(1+Math.exp(-1))>.5);
});
test('budget inversion respects the exact LMSR cost across price extremes',()=>{
 for(const y of [0,100,10000])for(const n of [0,100,10000])for(const side of ['yes','no'])for(const budget of [1,25,1000]){
  const m={q_yes:y,q_no:n,liquidity:100};const shares=sharesForBudget(m,side,budget);
  assert.ok(Number.isFinite(shares));assert.ok(quote(m,side,'buy',shares)<=budget+1e-8);
  if(shares<9999.9999)assert.ok(quote(m,side,'buy',shares+.0001)>=budget-1e-8);
 }
});
test('buy then sell reverses cost with no intervening trades',()=>{
 const total=quote(market,'yes','buy',73.1234);
 assert.ok(Math.abs(total-quote({...market,q_yes:73.1234},'yes','sell',73.1234))<1e-9);
});
test('stable cost avoids overflow for large outstanding quantities',()=>{
 assert.ok(Number.isFinite(cost(1000000,0,100)));
 assert.equal(cost(1000000,0,100),1000000);
});
