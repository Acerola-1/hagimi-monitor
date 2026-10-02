"""复用正式版调色板，仅裁掉依赖实时负载模型的未使用方法。"""
from pathlib import Path
import re
import sys

repo, output = map(Path, sys.argv[1:])
source = (repo / 'HagimiMonitor/MonitorPalette.swift').read_text()
source, count = re.subn(
    r'    func liveDot\(for loadLevel: MenuBarComputeLoadLevel\) -> Color \{\n.*?\n    \}\n',
    '', source, count=1, flags=re.S)
if count != 1:
    raise SystemExit('MonitorPalette adapter no longer matches; inspect source before building')
support = '''
enum MonitorColorSchemePreference { case balanced, vibrant }
enum MonitorSeverity { case calm, warning, critical }
enum MonitorKind { case cpu, gpu, memory, storage, network, battery, fan, bluetooth }
'''
output.write_text(source + support)
