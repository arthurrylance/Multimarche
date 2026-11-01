import test from 'node:test';import assert from 'node:assert/strict';import {currentPosition,projectPosition} from '../src/position-preview.mjs';import {netPreview,quote} from '../src/math.mjs';
const near=(a,b)=>assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`),book={execution_model:'clob'},amm={execution_model:'amm',q_yes:0,q_no:0,liquidity:400,initial_probability:.5};
test('current return uses executable sale prices and weighted purchase cost, not displayed percentages',()=>{
 const p=currentPosition({market:amm,held:100,basis:50});near(p.now.return,quote(amm,'yes','sell',100));near(p.now.profit,p.now.return-50);near(p.yes.return,100);near(p.yes.profit,50);near(p.no.return,0);near(p.no.profit,-50);
 const illiquid=currentPosition({market:book,held:-100,basis:30,bids:[{price:.6,size:20}]});assert.equal(illiquid.now.return,null);near(illiquid.liquidReturn,12);near(illiquid.no.profit,70);
});
test('partial closing realises only its allocated cost and preserves the basis of remaining shares',()=>{
 const p=projectPosition({market:book,held:100,basis:40,side:'no',quantity:30,limit:.4,levels:[{price:.4,size:1000}]});assert.equal(p.change,'Reduces Yes');near(p.shares,70);near(p.basis,28);near(p.cash,18);near(p.realised,6);near(p.yes.return,70);near(p.yes.profit,42);near(p.no.profit,-28);
});
test('crossing zero sells the old position before buying the new one and keeps realised and future profit distinct',()=>{
 const p=projectPosition({market:book,held:50,basis:20,side:'no',quantity:70,limit:.4,levels:[{price:.3,size:20},{price:.4,size:100}]});assert.equal(p.side,'NO');near(p.shares,20);assert.equal(p.change,'Switches to No');near(p.cash,24);near(p.realised,12);near(p.basis,8);near(p.no.return,20);near(p.no.profit,12);near(p.yes.profit,-8);
 const close=projectPosition({market:book,held:50,basis:20,side:'no',quantity:50,limit:.4,levels:[{price:.4,size:50}],debt:15});near(close.cash,15);near(close.realised,10);near(close.basis,0);near(close.yes.return,0);near(close.no.return,0);near(close.debt,0);
});
test('borrowing changes net returned cash without being mistaken for trading profit',()=>{
 const p=projectPosition({market:book,held:0,basis:0,side:'yes',quantity:200,limit:.5,levels:[{price:.5,size:200}],draw:90});near(p.cash,-10);near(p.basis,100);near(p.yes.return,110);near(p.yes.profit,100);near(p.no.return,-90);near(p.no.profit,-100);
});
test('order-book previews distinguish immediate matches, reserves and hypothetical full fills',()=>{
 const p=projectPosition({market:book,held:0,basis:0,side:'yes',quantity:100,limit:.5,levels:[{price:.4,size:20}],releasedReserve:5});near(p.cash,-8);near(p.reserved,40);near(p.availableCash,-43);near(p.pending,80);near(p.basis,48);near(p.yes.profit,52);
 const fak=projectPosition({market:book,held:0,basis:0,side:'yes',quantity:100,limit:.5,levels:[{price:.4,size:20}],tif:'FAK'});near(fak.shares,20);near(fak.basis,8);near(fak.reserved,0);
 const fok=projectPosition({market:book,held:0,basis:0,side:'yes',quantity:100,limit:.5,levels:[{price:.4,size:20}],tif:'FOK'});assert.equal(fok.failed,true);assert.equal(fok.change,'No position change');near(fok.cash,0);near(fok.shares,0);
});
test('automatic direction changes conserve combined realised and future profit at different initial likelihoods',()=>{
 for(const prior of [.1,.5,.9])for(const held of [-100,0,100])for(const side of ['yes','no'])for(const quantity of [10,100,150]){const m={...amm,initial_probability:prior,q_yes:Math.max(held,0),q_no:Math.max(-held,0)},basis=Math.abs(held)*.4,p=projectPosition({market:m,held,basis,side,quantity}),legacy=netPreview(held,basis,side,quantity,quote(m,side,'buy',quantity));near(p.cash,legacy.cash);near(p.yes.profit+p.realised,legacy.yes);near(p.no.profit+p.realised,legacy.no);}
});
