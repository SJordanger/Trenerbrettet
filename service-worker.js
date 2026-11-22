const CACHE = 'trenerbrettet-pwa-v85';
const ASSETS = ['./', './index.html', './supabase-config.js', './game-formats.js', './manifest.webmanifest', './icon-180.png', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)));self.skipWaiting();});
self.addEventListener('activate', e=>{e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('trenerbrettet-pwa-')&&k!==CACHE).map(k=>caches.delete(k)))));self.clients.claim();});
self.addEventListener('fetch',e=>{if(e.request.method!=='GET'||new URL(e.request.url).origin!==self.location.origin)return; e.respondWith(fetch(e.request).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));}return response;}).catch(()=>caches.match(e.request)));});

self.addEventListener('push',event=>{let data={};try{data=event.data?.json()||{};}catch(_){return;}if(!data.title)return;event.waitUntil(self.registration.showNotification(data.title,{body:data.body||'',icon:'./icon-192.png',badge:'./icon-192.png',tag:data.tag||'tb-live',data:{url:data.url||'./live.html'}}));});
self.addEventListener('notificationclick',event=>{event.notification.close();const url=new URL(event.notification.data?.url||'./live.html',self.location.origin).href;event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(all=>{for(const client of all){if(client.url===url){client.focus();return;}}return clients.openWindow(url);}));});
