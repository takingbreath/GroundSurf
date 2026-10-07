// Original generator fixture is MIT licensed; see Sources/LICENSE-original.txt.
process.chdir(require('node:path').resolve(__dirname,'..'));
const fs=require('fs'),vm=require('vm'),crypto=require('crypto'),{performance}=require('perf_hooks');const optimized=fs.readFileSync('Sources/generator.js','utf8');
function make(seed,modern){const c={console:{log(){}},Date,Math:Object.create(Math),window:{location:{href:'file:///quality?seed='+seed},btoa:s=>Buffer.from(s).toString('base64')},document:{addEventListener(){}}};c.self=c;vm.createContext(c);if(modern)vm.runInContext(optimized,c);else {let i=0;for(const m of fs.readFileSync('tests/fixtures/upstream-original.html','utf8').matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)){if(i===6)break;vm.runInContext(i===5 ? m[1].split('  document.addEventListener("mousemove"')[0] : m[1],c);i++;}}return c;}
const results=[];
for(const seed of ['GroundSurf-profile','dense-forest','river-boats']){
 const runs=[];
 for(const modern of [false,true]){const c=make(seed,modern);c.MEM.windx=1422;const t=performance.now();c.chunkloader(0,2446);const output=c.MEM.chunks.map(x=>x.canv).join('');runs.push({ms:performance.now()-t,bytes:Buffer.byteLength(output),hash:crypto.createHash('sha256').update(output).digest('hex')});}
 if(runs[0].hash!==runs[1].hash)throw Error('Geometry changed for '+seed);results.push({seed,baseline:runs[0],optimized:runs[1]});console.log(JSON.stringify(results.at(-1)));}
// Compare stored commands with the SVG geometry for the same complete object sequence.
const a=make('GroundSurf-profile',false),b=make('GroundSurf-profile',true);a.MEM.windx=b.MEM.windx=1422;b.CommandBackend.enabled=true;a.chunkloader(0,2446);b.chunkloader(0,2446);
const expected=[];
for(const chunk of a.MEM.chunks)for(const m of chunk.canv.matchAll(/<polyline points='([^']*)' style='([^']*)'\/>/g)){const styles=Object.fromEntries(m[2].split(';').map(s=>s.split(':')));expected.push({type:'polyline',points:m[1].trim().split(/\s+/).flatMap(p=>p.split(',').map(Number)),fill:styles.fill,stroke:styles.stroke,width:Number(styles['stroke-width'])});}
const actual=b.MEM.chunks.flatMap(c=>c.commands).filter(c=>c.type==='polyline').map(({type,points,fill,stroke,width})=>({type,points:Array.from(points),fill,stroke,width}));
if(JSON.stringify(expected)!==JSON.stringify(actual))throw Error('Command geometry differs');
const nativeBounds=b.MEM.chunks.filter(c=>c.bounds[2]>=600&&c.bounds[0]<=2446);
const rawText="<text font-size='12' font-family='Verdana' style='fill:rgba(100,100,100,0.9)' text-anchor='middle' transform='translate(10,20) rotate(30)'>Test</text><circle cx='10' cy='20' r='5' fill='red'/>";const test={canv:rawText};b.CommandBackend.attach(test);if(test.commands.map(x=>x.type).join(',')!=='text,circle')throw Error('Primitive support failed');
const data={result:'PASS',fixedSeedOutput:results,exactCommandPolylines:actual.length,primitiveSupport:true,visibleBoundsObjects:nativeBounds.length};console.log('PASS: exact geometry, styles, layering, primitive decoding');
