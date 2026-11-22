const {reply}=require('./_shared');
exports.handler=async()=>process.env.VAPID_PUBLIC_KEY?reply(200,{publicKey:process.env.VAPID_PUBLIC_KEY}):reply(503,{error:'VAPID er ikke konfigurert'});
