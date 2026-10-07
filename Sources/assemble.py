from pathlib import Path
root=Path(__file__).resolve().parent
worker=(root/'worker.js').read_text()
marker='// Generator and painter are inserted here when the app\'s bundled HTML is built.'
worker=worker.replace(marker,(root/'generator.js').read_text()+'\n'+(root/'painter.js').read_text())
html='''<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;overflow:hidden;background:#f4ecd9}html[data-dark="true"],html[data-dark="true"] body{background:#141414}html[data-dark="true"] canvas{filter:invert(1) grayscale(1)}canvas{position:absolute;left:0;top:0;will-change:transform}</style></head><body><canvas id="scene" width="0" height="0"></canvas>'''
html+='<script id="groundsurf-worker" type="text/groundsurf-worker">'+worker+'</script>'
html+='<script>'+(root/'painter.js').read_text()+'</script><script>'+(root/'viewer.js').read_text()+'</script></body></html>'
(root/'landscape.html').write_text(html)
