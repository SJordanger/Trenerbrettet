// V85: Eget manifest per livekamp, slik at hjemskjermikonet paa iPhone aapner riktig kamp.
// Funksjonen leser ingen data fra databasen; den bygger bare manifestet ut fra lenken.
const {validToken}=require('./_shared');
exports.handler=async event=>{
 const token=(event.queryStringParameters||{}).t||'';
 const url=validToken(token)?'/live.html?t='+token:'/live.html';
 const manifest={name:'Følg kampen',short_name:'Følg kampen',id:url,start_url:url,scope:'/',display:'standalone',background_color:'#0d1924',theme_color:'#0d1924',
  icons:[{src:'/icon-192.png',sizes:'192x192',type:'image/png'},{src:'/icon-512.png',sizes:'512x512',type:'image/png'}]};
 return {statusCode:200,headers:{'Content-Type':'application/manifest+json','Cache-Control':'no-store'},body:JSON.stringify(manifest)};
};
