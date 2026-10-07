var selfWindow={location:{href:'file:///GroundSurf'},btoa:self.btoa.bind(self)};
var window=selfWindow;
var document={addEventListener(){}};
console.log=function(){};
// Generator and painter are inserted here when the app's bundled HTML is built.
let activeSeed='',offscreen=null;
function prepareScene(data) {
  const started=performance.now();
  if(data.kind==='init') {
    activeSeed=data.seed;Math.seed(activeSeed);CommandBackend.enabled=true;
  }
  MEM.windx=800*data.viewportWidth/data.height;MEM.windy=800;
  const start=data.start;
  // Bounds-based retention keeps long ridges until their last pixels are behind the buffer.
  const cutoff=start-2048;
  MEM.chunks=MEM.chunks.filter(c=>c.bounds[2]>=cutoff);
  for(const key of Object.keys(MEM.planmtx))if(Number(key)*5<cutoff-512)delete MEM.planmtx[key];
  MEM.xmin=Math.max(MEM.xmin,cutoff);
  chunkloader(start,start+MEM.windx+1024);
  const scale=data.height/(800/1.142);
  const worldRight=start+data.width/scale;
  const commands=[];
  let geometryBytes=0;
  for(const chunk of MEM.chunks) {
    for(const command of chunk.commands)geometryBytes+=(command.points?.byteLength || 0);
    if(chunk.bounds[2]<start || chunk.bounds[0]>worldRight)continue;
    for(const command of chunk.commands)if(command.bounds[2]>=start && command.bounds[0]<=worldRight)commands.push(command);
  }
  const stats={objects:MEM.chunks.length,planning:Object.keys(MEM.planmtx).length,geometryBytes,commands:commands.length,seed:activeSeed};
  const generated=performance.now();
  if(typeof OffscreenCanvas==='function' && typeof OffscreenCanvas.prototype.transferToImageBitmap==='function') {
    if(!offscreen)offscreen=new OffscreenCanvas(data.width,data.height);
    paintScene(offscreen,commands,start,data.width,data.height);
    const bitmap=offscreen.transferToImageBitmap();
    self.postMessage({kind:'scene',request:data.request,start,width:data.width,height:data.height,bitmap,stats,generationMs:generated-started,paintMs:performance.now()-generated},[bitmap]);
  } else {
    // Keep generation off the main thread even on systems without worker canvas support.
    self.postMessage({kind:'scene',request:data.request,start,width:data.width,height:data.height,commands,stats,generationMs:generated-started,paintMs:null});
  }
}
self.onmessage=function(event) {
  try {prepareScene(event.data);}
  catch(error) {
    CommandBackend.pending.clear();
    self.postMessage({kind:'error',request:event.data.request,message:String(error)});
  }
};
