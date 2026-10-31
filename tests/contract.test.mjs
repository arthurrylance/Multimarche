import test from 'node:test';
import assert from 'node:assert/strict';
import ganache from 'ganache';
import {BrowserProvider,ContractFactory,sha256,toUtf8Bytes,ZeroHash} from 'ethers';
import {readFileSync} from 'node:fs';
const artifact=JSON.parse(readFileSync(new URL('../src/audit-contract.json',import.meta.url)));
test('audit contract enforces owner, sequence, payload integrity and append-only history',async()=>{
 const node=ganache.provider({chain:{chainId:31337},logging:{quiet:true}});
 try{
  const provider=new BrowserProvider(node),owner=await provider.getSigner(0),other=await provider.getSigner(1);
  const contract=await new ContractFactory(artifact.abi,artifact.bytecode,owner).deploy();await contract.waitForDeployment();
  const payload='{"seq":1,"kind":"genesis"}',hash=sha256(toUtf8Bytes(payload));
  await assert.rejects(async()=>await(await contract.connect(other).appendBatch(1,ZeroHash,[hash],[payload])).wait());
  await assert.rejects(async()=>await(await contract.appendBatch(2,ZeroHash,[hash],[payload])).wait());
  await assert.rejects(async()=>await(await contract.appendBatch(1,ZeroHash,[ZeroHash],[payload])).wait());
  await(await contract.appendBatch(1,ZeroHash,[hash],[payload])).wait();
  assert.equal(await contract.height(),1n);assert.equal(await contract.head(),hash);assert.equal(await contract.hashAt(1),hash);
  await assert.rejects(async()=>await(await contract.appendBatch(1,ZeroHash,[hash],[payload])).wait());
  const next='{"seq":2,"kind":"transfer"}',h2=sha256(toUtf8Bytes(next));
  await(await contract.appendBatch(2,hash,[h2],[next])).wait();
  assert.equal(await contract.height(),2n);assert.equal(await contract.hashAt(1),hash);assert.equal(await contract.head(),h2);
  const events=await contract.queryFilter(contract.filters.Record());assert.equal(events.length,2);assert.equal(events[0].args.payload,payload);
 }finally{await node.disconnect();}
});
