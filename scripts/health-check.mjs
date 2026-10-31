// Public availability checks only. No account sessions, private rows or secrets.
const app='https://multimarche.vercel.app';
const supabase='https://vakkbgsooubqpmdekixr.supabase.co';
const publishable='sb_publishable_TaBmHyqoiGBiOEpVb0L86g_28xH5B_6';
async function request(url,headers={}){const response=await fetch(url,{headers,signal:AbortSignal.timeout(20000)});if(!response.ok)throw new Error(`${new URL(url).pathname}: HTTP ${response.status}`);return response;}
const checks=[
 (async()=>{const response=await request(app);const html=await response.text();if(!html.includes('<title>Multimarché'))throw new Error('The app returned an unexpected page, possibly an access screen.');const script=html.match(/<script[^>]+src="([^"]+\/assets\/[^\"]+|\/assets\/[^\"]+)"/);if(!script)throw new Error('App JavaScript entry not found');const asset=new URL(script[1],app);if(asset.origin!==app)throw new Error('Unexpected asset origin');const js=await request(asset);if(!js.headers.get('content-type')?.includes('javascript'))throw new Error('App JavaScript has the wrong content type');console.log('PASS: website and JavaScript entry');})(),
 (async()=>{await request(supabase+'/auth/v1/health',{apikey:publishable});console.log('PASS: Supabase Auth health');})()
];
const results=await Promise.allSettled(checks);let failures=0;for(const r of results)if(r.status==='rejected'){failures++;console.error('FAIL:',r.reason.message);}if(failures)process.exitCode=1;
