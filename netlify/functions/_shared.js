const {createClient}=require('@supabase/supabase-js');
const headers={'Content-Type':'application/json','Cache-Control':'no-store'};
const reply=(statusCode,data)=>({statusCode,headers,body:JSON.stringify(data)});
function db(){if(!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)throw Error('Supabase servervariabler mangler');return createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});}
function body(event){try{return JSON.parse(event.body||'{}')}catch{return {}}}
function validToken(token){return typeof token==='string'&&/^[a-f0-9]{64}$/.test(token)}
// V85: samme utloepsregel som tb_live_view i databasen.
const HOUR=3600*1000;
function liveValid(row){if(!row)return false;const now=Date.now();if(now-new Date(row.created_at).getTime()>7*24*HOUR)return false;return row.payload?.status!=='finished'||now-new Date(row.updated_at).getTime()<=6*HOUR;}
async function activeMatch(client,token){const {data,error}=await client.from('tb_live_matches').select('token,owner_id,payload,active,created_at,updated_at').eq('token',token).eq('active',true).maybeSingle();if(error)throw error;return liveValid(data)?data:null}
module.exports={reply,db,body,validToken,activeMatch};
