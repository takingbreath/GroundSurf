let scene=document.getElementById('scene');
const workerSource=document.getElementById('groundsurf-worker').textContent;
const sourceURL=URL.createObjectURL(new Blob([workerSource],{type:'text/javascript'}));
const worker=new Worker(sourceURL);URL.revokeObjectURL(sourceURL);
let hasScene=false,cursor=0,renderAt=0,running=true,speed=12,last=0,pending=false,nextScene=null,frames=0,request=0,lastError='',retryAt=0,stats={},generationMs=0,paintMs=0;
let appearance='light';
const systemAppearance=matchMedia('(prefers-color-scheme: dark)');
function applyAppearance(){document.documentElement.dataset.appearance=appearance;document.documentElement.dataset.dark=String(appearance==='purple' || appearance==='dark' || appearance==='system' && systemAppearance.matches);}
systemAppearance.addEventListener('change',applyAppearance);
const seed=new URLSearchParams(location.search).get('seed') || String(Date.now());
function dimensions(){const scale=innerHeight/(800/1.142);return {width:Math.ceil(innerWidth+1024*scale),height:innerHeight,viewportWidth:innerWidth};}
function prepare(start,kind='prepare') {
  if(pending || performance.now()<retryAt)return;
  pending=true;
  worker.postMessage({kind,request:++request,seed,start,...dimensions()});
}
function paintAndCommit(result) {
  const staging=document.createElement('canvas');
  staging.width=result.width;staging.height=result.height;
  if(result.bitmap){staging.getContext('2d').drawImage(result.bitmap,0,0);result.bitmap.close();}
  else paintScene(staging,result.commands,result.start,result.width,result.height);
  // Commit only after the complete frame exists, so a paint failure preserves the old one.
  const oldScene=scene;staging.id='scene';oldScene.replaceWith(staging);scene=staging;oldScene.width=0;oldScene.height=0;
  hasScene=true;renderAt=result.start;stats=result.stats;generationMs=result.generationMs;paintMs=result.paintMs;
  position();
}
function position(){scene.style.transform=`translate3d(${-(cursor-renderAt)*innerHeight/(800/1.142)}px,0,0)`;}
worker.onmessage=function(event) {
  const result=event.data;
  if(result.request!==request){result.bitmap?.close();return;}
  pending=false;
  if(result.kind==='error'){lastError=result.message;retryAt=performance.now()+5000;return;}
  lastError='';
  try {
    if(frames===0 || result.start<=cursor)paintAndCommit(result);
    else {nextScene?.bitmap?.close();nextScene=result;}
  }catch(error){result.bitmap?.close();lastError=String(error);retryAt=performance.now()+5000;}
};
worker.onerror=function(event){pending=false;lastError=event.message;retryAt=performance.now()+5000;setTimeout(()=>location.reload(),5000);};
function frame(t) {
  if(!running)return;
  // Do not scroll the initial canvas until its first scene is ready.
  if(!hasScene){last=t;if(!pending && retryAt && t>=retryAt)prepare(0);return;}
  if(lastError){last=t;if(!pending && t>=retryAt)prepare(renderAt+512);return;}
  if(last)cursor+=Math.min((t-last)/1000,.1)*speed;
  last=t;
  try {
    if(nextScene && cursor>=nextScene.start){const ready=nextScene;nextScene=null;paintAndCommit(ready);}
    if(!pending && !nextScene && cursor>=renderAt+256)prepare(renderAt+512);
    position();frames++;
  }catch(error){lastError=String(error);retryAt=t+5000;}
}
window.wallpaper={appearance(value){appearance=['light','dark','purple','system'].includes(value)?value:'light';applyAppearance();},pause(p){running=!p;last=0;},speed(v){speed=v;},tick(){frame(performance.now());},stats(){return {...stats,appearance,dark:document.documentElement.dataset.dark==='true',position:cursor,frames,busy:pending,prepared:!!nextScene,lastError,generationMs,paintMs,bitmapWidth:scene.width,bitmapHeight:scene.height};}};
window.addEventListener('resize',()=>{nextScene?.bitmap?.close();nextScene=null;pending=false;prepare(cursor);});
window.addEventListener('pagehide',()=>{nextScene?.bitmap?.close();worker.terminate();});
prepare(0,'init');
