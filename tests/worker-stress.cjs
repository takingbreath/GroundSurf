process.chdir(require('node:path').resolve(__dirname,'..'));
const fs=require('fs'),vm=require('vm'),{performance}=require('perf_hooks');
const generator=fs.readFileSync('Sources/generator.js','utf8'),tail=fs.readFileSync('Sources/worker.js','utf8').split('// Generator and painter are inserted here when the app\'s bundled HTML is built.')[1];
let message;const c={console:{log(){}},Date,Math:Object.create(Math),performance,window:{location:{href:'file:///stress'},btoa:s=>Buffer.from(s).toString('base64')},document:{addEventListener(){}},postMessage:x=>message=x};c.self=c;vm.createContext(c);vm.runInContext(generator,c);vm.runInContext(tail,c);
const samples=[];
for(let i=0;i<100;i++){c.onmessage({data:{kind:i?'prepare':'init',request:i+1,start:i*512,width:2147,height:768,viewportWidth:1024,seed:'worker-stress'}});if(message.kind!=='scene')throw Error(JSON.stringify(message));if(i%10===0)samples.push({start:i*512,...message.stats,ms:message.generationMs});}
if(samples.some(s=>s.objects>500||s.planning>2000||s.geometryBytes>100*1024*1024))throw Error('Unexpected growth');
// A wide ridge remains visible after its origin falls behind the original 512-unit threshold.
c.MEM.chunks=[{commands:[{type:'polyline',points:new Float64Array([0,0,1500,0]),fill:'black',stroke:'none',width:0,bounds:[0,0,1500,0]}],bounds:[0,0,1500,0],x:0,y:0}];c.chunkloader=()=>{};c.onmessage({data:{kind:'prepare',request:101,start:600,width:2147,height:768,viewportWidth:1024}});if(message.commands.length!==1)throw Error('Visible ridge removed');
// Error reply must release pending command references and permit a subsequent request.
c.chunkloader=()=>{throw Error('simulated failure')};c.onmessage({data:{kind:'prepare',request:102,start:600,width:2147,height:768,viewportWidth:1024}});if(message.kind!=='error')throw Error('Missing error response');c.chunkloader=()=>{};c.onmessage({data:{kind:'prepare',request:103,start:600,width:2147,height:768,viewportWidth:1024}});if(message.kind!=='scene')throw Error('Did not recover');
console.log('PASS: 100 worker scenes, bounded geometry, wide-ridge visibility, error recovery');
