import {useEffect,useState} from 'react';
import {supabase} from './db';
import {ExternalLink,ShieldCheck} from 'lucide-react';
import type {AuditBlock} from './audit.mjs';
type ChainConfig={address:string|null;deployment_tx:string|null};
type ChainStatus={height:number;head:string};
const short=(s:string)=>`${s.slice(0,9)}…${s.slice(-6)}`;
export default function AuditPage({admin,tick,notify}:{admin:boolean;tick:number;notify:(s:string)=>void}){
 const[blocks,setBlocks]=useState<AuditBlock[]>([]),[all,setAll]=useState<AuditBlock[]|null>(null),[economy,setEconomy]=useState<Record<string,number>>({}),[config,setConfig]=useState<ChainConfig>({address:null,deployment_tx:null}),[chain,setChain]=useState<ChainStatus|null>(null),[events,setEvents]=useState<{id:string;action:string;reason:string;created_at:string}[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState(''),[verified,setVerified]=useState(false),[wallet,setWallet]=useState(''),[address,setAddress]=useState(''),[deploymentTx,setDeploymentTx]=useState('');
 const load=async()=>{
  const rs=await Promise.all([supabase.from('audit_blocks').select('*').order('seq',{ascending:false}).limit(50),supabase.rpc('economy_status'),supabase.from('chain_config').select('address,deployment_tx').single(),supabase.from('admin_events').select('id,action,reason,created_at').order('created_at',{ascending:false}).limit(30)]);
  for(const r of rs)if(r.error)throw r.error;
  setBlocks(rs[0].data as AuditBlock[]);setEconomy(rs[1].data??{});setConfig(rs[2].data as ChainConfig);setEvents(rs[3].data??[]);
 };
 useEffect(()=>{void load().catch(e=>setError(e.message));setVerified(false);setAll(null);},[tick]);
 const readChain=async(contractAddress:string)=>{
  const {JsonRpcProvider,Contract}=await import('ethers');const artifact=await import('./audit-contract.json');
  const provider=new JsonRpcProvider('https://ethereum-sepolia-rpc.publicnode.com',11155111,{staticNetwork:true});
  try{const c=new Contract(contractAddress,artifact.abi,provider);const [height,head]=await Promise.all([c.height(),c.head()]);const value={height:Number(height),head:String(head).slice(2)};setChain(value);return value;}finally{provider.destroy();}
 };
 useEffect(()=>{if(config.address)void readChain(config.address).catch(()=>{setChain(null);});},[config.address,tick]);
 const run=async(fn:()=>Promise<void>)=>{setBusy(true);setError('');try{await fn();}catch(e){setError((e as {shortMessage?:string;message?:string})?.shortMessage??(e as {message?:string})?.message??'Action failed.');}finally{setBusy(false);}};
 const fetchVerified=async()=>{
  const items:AuditBlock[]=[];let from=0;
  for(;;){const{data,error}=await supabase.from('audit_blocks').select('*').order('seq').range(from,from+499);if(error)throw error;items.push(...data as AuditBlock[]);if((data??[]).length<500)break;from+=500;}
  const{verifyLedger}=await import('./audit.mjs');verifyLedger(items);setVerified(true);setAll(items);return items;
 };
 const signer=async()=>{
  const ethereum=(window as unknown as {ethereum?:{request:(a:{method:string;params?:unknown[]})=>Promise<unknown>}}).ethereum;
  if(!ethereum)throw new Error('Open this page in a browser with a wallet such as MetaMask. Use a separate test wallet.');
  await ethereum.request({method:'eth_requestAccounts'});
  if(await ethereum.request({method:'eth_chainId'})!=='0xaa36a7')await ethereum.request({method:'wallet_switchEthereumChain',params:[{chainId:'0xaa36a7'}]});
  const {BrowserProvider}=await import('ethers');const provider=new BrowserProvider(ethereum);
  if((await provider.getNetwork()).chainId!==11155111n)throw new Error('Switch your wallet to Sepolia.');
  const account=await provider.getSigner();setWallet(await account.getAddress());return account;
 };
 const deploy=()=>void run(async()=>{
  const s=await signer();const {ContractFactory}=await import('ethers');const artifact=await import('./audit-contract.json');
  const contract=await new ContractFactory(artifact.abi,artifact.bytecode,s).deploy();const tx=contract.deploymentTransaction();if(!tx)throw new Error('Deployment transaction missing');
  // Retain recovery details before saving, so a failed database write never requires redeployment.
  setAddress(await contract.getAddress());setDeploymentTx(tx.hash);await contract.waitForDeployment();
  const {error}=await supabase.rpc('set_chain',{p_address:await contract.getAddress(),p_tx:tx.hash});if(error)throw error;
  await load();notify('Sepolia contract deployed. Publish the pending records next.');
 });
 const saveExisting=()=>void run(async()=>{
  const s=await signer();const {Contract,id}=await import('ethers');const artifact=await import('./audit-contract.json');const c=new Contract(address,artifact.abi,s);
  if(await c.VERSION()!==id('MULTIMARCHE_AUDIT_V1')||(await c.owner()).toLowerCase()!==(await s.getAddress()).toLowerCase())throw new Error('The contract version or owner does not match.');
  const receipt=await s.provider!.getTransactionReceipt(deploymentTx);if(!receipt||receipt.status!==1||receipt.contractAddress?.toLowerCase()!==address.toLowerCase())throw new Error('Provide the confirmed contract deployment transaction.');
  const{error}=await supabase.rpc('set_chain',{p_address:address,p_tx:deploymentTx});if(error)throw error;await load();
 });
 const publish=()=>void run(async()=>{
  if(!config.address)throw new Error('Deploy or connect the audit contract first.');const items=await fetchVerified();const s=await signer();const {Contract}=await import('ethers');const artifact=await import('./audit-contract.json');const c=new Contract(config.address,artifact.abi,s);
  if((await c.owner()).toLowerCase()!==(await s.getAddress()).toLowerCase())throw new Error('Use the wallet that deployed the audit contract.');
  const height=Number(await c.height()),head=String(await c.head()).slice(2);if(head!==(height?items[height-1]?.hash:'0'.repeat(64)))throw new Error('The blockchain and database history do not match. Publication stopped.');
  const batch=items.slice(height,height+10);if(!batch.length){notify('All records are already published.');return;}
  const tx=await c.appendBatch(height+1,'0x'+head,batch.map(b=>'0x'+b.hash),batch.map(b=>b.payload));notify('Transaction submitted. Waiting for Sepolia confirmation.');await tx.wait();await readChain(config.address);notify(`${batch.length} records confirmed on Sepolia.`);
 });
 const download=()=>void run(async()=>{const items=all??await fetchVerified();const blob=new Blob([JSON.stringify(items,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='multimarche-transactions.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
 return <><div className="page-heading compact"><h1>Transactions</h1><button className="secondary" disabled={busy} onClick={download}>Export records</button></div><div className="portfolio-stats"><div><span>Total issued</span><strong>◈ {Number(economy.total_supply??0).toLocaleString()}</strong></div><div><span>Treasury</span><strong>◈ {Number(economy.treasury??0).toLocaleString(undefined,{maximumFractionDigits:2})}</strong></div><div><span>Ledger records</span><strong>{economy.height??0}</strong></div></div><section className="settings-card audit-status"><h2><ShieldCheck size={19}/>Ledger verification</h2><p>Every credit transfer has a matching debit. Starting credits and market reserves come from treasury. Admin issuance increases the recorded supply.</p><button className="secondary" disabled={busy} onClick={()=>void run(async()=>{await fetchVerified();notify('Hashes, transfers and total supply verified.');})}>{verified?'Verified ✓':'Verify complete ledger'}</button></section><section className="settings-card audit-status"><h2>Sepolia blockchain</h2><p>Records are published in batches using the admin’s test wallet. Publication contains pseudonymous account IDs and credit amounts. Usernames, market titles and admin notes stay off-chain. Balances and trading remain in Supabase.</p>{config.address?<><a href={`https://sepolia.etherscan.io/address/${config.address}`} target="_blank" rel="noreferrer">{short(config.address)} <ExternalLink size={12}/></a><p>{chain?`${chain.height} / ${economy.height??0} records confirmed on-chain`:'Checking on-chain history…'}</p>{chain&&<p className="tiny muted">Head: <code>{short(chain.head)}</code></p>}{admin&&<button className="primary" disabled={busy} onClick={publish}>{busy?'Waiting…':'Publish next 10 records'}</button>}<button className="text-button" disabled={busy} onClick={()=>void run(async()=>{await readChain(config.address!);})}>Refresh chain status</button></>:<><p><b>Not activated.</b> No records have been published to a public blockchain yet.</p>{admin&&<><p className="tiny muted">Use a separate wallet with Sepolia test ETH. No real-value funds are needed. You approve deployment and publication in your wallet.</p><button className="primary" disabled={busy} onClick={deploy}>{busy?'Waiting for wallet…':'Connect wallet & deploy on Sepolia'}</button><details><summary>Connect an existing deployment</summary><label>Contract address<input value={address} onChange={e=>setAddress(e.target.value)} placeholder="0x…"/></label><label>Deployment transaction<input value={deploymentTx} onChange={e=>setDeploymentTx(e.target.value)} placeholder="0x…"/></label><button className="secondary" disabled={busy||!address||!deploymentTx} onClick={saveExisting}>Verify & connect</button></details></>}</>}{wallet&&<small>Wallet: {short(wallet)}</small>}{error&&<p className="form-error" role="alert">{error}</p>}</section><h2 className="section-title">Latest transfers & issuance</h2><div className="audit-table">{blocks.map(b=>{const p=JSON.parse(b.payload);return <details key={b.seq}><summary><span>#{b.seq} · {p.kind==='genesis'?'Opening supply':p.kind==='mint'?`Issuance: +${p.amount}`:`${p.reason} · ${Number(p.amount).toLocaleString(undefined,{maximumFractionDigits:4})} credits`}</span><code>{short(b.hash)}</code></summary><pre>{JSON.stringify(p,null,2)}</pre><small>{new Date(b.created_at).toLocaleString()}</small></details>;})}</div><h2 className="section-title">Admin actions</h2><div className="activity-list">{events.map(e=><div key={e.id}><span><b>{e.action.replaceAll('_',' ')}</b><small>{e.reason}</small></span><span>{new Date(e.created_at).toLocaleString()}</span></div>)}{!events.length&&<p className="section-note muted">No admin actions.</p>}</div></>;
}
