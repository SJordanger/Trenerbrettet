const {reply,db,body,validToken,activeMatch}=require('./_shared');
exports.handler=async event=>{
 if(event.httpMethod!=='POST')return reply(405,{error:'Method not allowed'});
 try{const {token,subscription}=body(event);if(!validToken(token)||!subscription?.endpoint?.startsWith('https://')||!subscription.keys?.p256dh||!subscription.keys?.auth||JSON.stringify(subscription).length>5000)return reply(400,{error:'Ugyldig abonnement'});
 const client=db();if(!await activeMatch(client,token))return reply(404,{error:'Kampen er ikke tilgjengelig'});
 const {error}=await client.from('tb_push_subscriptions').upsert({token,endpoint:subscription.endpoint,subscription},{onConflict:'token,endpoint'});if(error)throw error;return reply(200,{ok:true});
 }catch(e){return reply(500,{error:'Registrering feilet'});}
};
