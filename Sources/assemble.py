from pathlib import Path
root=Path(__file__).resolve().parent
worker=(root/'worker.js').read_text()
marker='// Generator and painter are inserted here when the app\'s bundled HTML is built.'
worker=worker.replace(marker,(root/'generator.js').read_text()+'\n'+(root/'painter.js').read_text())
html='''<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;overflow:hidden;background:#f4ecd9}html[data-dark="true"],html[data-dark="true"] body{background:#141414}html[data-dark="true"] canvas{filter:invert(1) grayscale(1)}html[data-appearance="purple"],html[data-appearance="purple"] body{background:#2b1c40}html[data-appearance="purple"] canvas{filter:url(#purple-ink)}canvas{position:absolute;left:0;top:0;will-change:transform}</style></head><body><svg xmlns="http://www.w3.org/2000/svg" width="0" height="0" aria-hidden="true" style="position:absolute"><defs><filter id="purple-ink" x="0%" y="0%" width="100%" height="100%" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="-.14882 -.50064 -.05054 0 .82 -.14882 -.50064 -.05054 0 .76 -.14882 -.50064 -.05054 0 .90 0 0 0 1 0"/></filter></defs></svg><canvas id="scene" width="0" height="0"></canvas>'''
html+='<script id="groundsurf-worker" type="text/groundsurf-worker">'+worker+'</script>'
html+='<script>'+(root/'painter.js').read_text()+'</script><script>'+(root/'viewer.js').read_text()+'</script></body></html>'
(root/'landscape.html').write_text(html)
