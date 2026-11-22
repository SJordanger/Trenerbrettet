const {reply,db,body,validToken,activeMatch}=require('./_shared');
const webpush=require('web-push');
exports.handler=async event=>{
 if(event.httpMethod!=='POST')return reply(405,{error:'Method not allowed'});
 try{
 const {token}=body(event);if(!validToken(token))return reply(400,{error:'Ugyldig kamp'});
 const jwt=(event.headers.authorization||event.headers.Authorization||'').replace(/^Bearer\s+/i,'');if(!jwt)return reply(401,{error:'Innlogging kreves'});
 const client=db();const {data:{user},error:authError}=await client.auth.getUser(jwt);if(authError||!user)return reply(401,{error:'Ugyldig innlogging'});
 const match=await activeMatch(client,token);if(!match||match.owner_id!==user.id)return reply(403,{error:'Ingen tilgang'});
 if(!process.env.VAPID_PUBLIC_KEY||!process.env.VAPID_PRIVATE_KEY||!process.env.VAPID_SUBJECT)return reply(503,{error:'Push er ikke konfigurert'});
 webpush.setVapidDetails(process.env.VAPID_SUBJECT,process.env.VAPID_PUBLIC_KEY,process.env.VAPID_PRIVATE_KEY);
 const payload=match.payload||{};const events=Array.isArray(payload.events)?payload.events:[];
 const notifications=[];
 // Marker historiske maal som sett ved foerste utsending? Nei: nye abonnenter faar ikke gamle varsler fordi leveringsmarkoerer er globale.
 for(const goal of events){
  if(!goal.id)continue;
  // V85: appen merker mål som klare 30 s etter registrering, slik at treneren rekker aa angre.
  if(goal.pushReady!==true)continue;
  const key='goal:'+String(goal.id).slice(0,100);
  const {error:insertError}=await client.from('tb_push_deliveries').insert({token,event_key:key});
  if(insertError){if(insertError.code==='23505')continue;throw insertError;}
  const home=goal.side!=='away';const team=home?payload.home:payload.away;
  const name=home&&payload.showNames&&goal.scorerName?String(goal.scorerName).slice(0,80):null;
  const assist=home&&payload.showNames&&goal.assistName?' · Assist: '+String(goal.assistName).slice(0,80):'';
  notifications.push({title:'⚽ Mål! '+String(team||'Kampen').slice(0,60),body:(name?name+assist+' · ':'')+String(payload.homeScore||0)+'–'+String(payload.awayScore||0),tag:key,url:'/live.html#'+token});
 }
 const {data:subs,error:subError}=await client.from('tb_push_subscriptions').select('endpoint,subscription').eq('token',token).limit(500);if(subError)throw subError;
 let sent=0;for(const notification of notifications){for(const sub of subs||[]){try{await webpush.sendNotification(sub.subscription,JSON.stringify(notification),{TTL:3600});sent++;}catch(e){if(e.statusCode===404||e.statusCode===410)await client.from('tb_push_subscriptions').delete().eq('token',token).eq('endpoint',sub.endpoint);}}}
 return reply(200,{ok:true,sent});
 }catch(e){console.error('push-dispatch',e);return reply(500,{error:'Pushutsending feilet'});}
};
