// Shared by the worker and the fallback canvas renderer. Never changes geometry detail.
function paintScene(canvas, commands, start, width, height) {
  const scale=height/(800/1.142);
  if(canvas.width!==width)canvas.width=width;
  if(canvas.height!==height)canvas.height=height;
  const ctx=canvas.getContext('2d');
  ctx.save();
  try {
    ctx.setTransform(1,0,0,1,0,0);
    ctx.globalCompositeOperation='source-over';
    ctx.fillStyle='#ffffff';ctx.fillRect(0,0,width,height);
    ctx.scale(scale,scale);ctx.translate(-start,0);
    for(const command of commands) {
      if(command.type==='text') {
        ctx.save();ctx.translate(command.x,command.y);ctx.rotate(command.angle*Math.PI/180);
        ctx.font=command.size+'px '+command.family;ctx.textAlign='center';ctx.textBaseline='alphabetic';ctx.fillStyle=command.fill;
        ctx.fillText(command.text,0,0);ctx.restore();continue;
      }
      ctx.beginPath();
      if(command.type==='circle')ctx.arc(command.x,command.y,command.r,0,Math.PI*2);
      else {
        const points=command.points;
        if(!points.length)continue;
        ctx.moveTo(points[0],points[1]);
        for(let i=2;i<points.length;i+=2)ctx.lineTo(points[i],points[i+1]);
      }
      if(command.fill && command.fill!=='none'){ctx.fillStyle=command.fill;ctx.fill();}
      if(command.stroke && command.stroke!=='none' && command.width>0){ctx.strokeStyle=command.stroke;ctx.lineWidth=command.width;ctx.stroke();}
    }
    ctx.setTransform(1,0,0,1,0,0);
    ctx.globalCompositeOperation='multiply';ctx.fillStyle='#f4ecd9';ctx.fillRect(0,0,width,height);
  } finally {ctx.restore();}
}
