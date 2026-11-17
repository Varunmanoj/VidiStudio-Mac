#!/usr/bin/env python3
"""Reject Mac release code whose recorded OS/CPU requirements exceed the advertised minimum."""
import argparse
import plistlib
import struct,json,collections,sys
from pathlib import Path
records=[]
def version(v):return '.'.join(map(str,[(v>>16)&65535,(v>>8)&255,v&255]))
def inspect(f,offset=0):
 f.seek(offset);h=f.read(32)
 if len(h)<8:return []
 magic=h[:4]
 if magic in (b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca'):
  endian='>' if magic[:2]==b'\xca\xfe' else '<'; n=struct.unpack(endian+'I',h[4:8])[0];fat64=magic in (b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca');size=32 if fat64 else 20
  f.seek(offset+8);entries=f.read(size*n);out=[]
  for i in range(n):
   e=entries[i*size:(i+1)*size];off=struct.unpack(endian+('Q' if fat64 else 'I'),e[8:16 if fat64 else 12])[0];out+=inspect(f,offset+off)
  return out
 if magic not in (b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xfe\xed\xfa\xce'):return []
 endian='<' if magic[:1] in (b'\xcf',b'\xce') else '>';is64=magic in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf');cpu=struct.unpack(endian+'I',h[4:8])[0];ncmd=struct.unpack(endian+'I',h[16:20])[0];pos=offset+(32 if is64 else 28);out=[]
 for _ in range(ncmd):
  f.seek(pos);cmd,sz=struct.unpack(endian+'II',f.read(8));data=f.read(sz-8)
  if cmd==0x32:
   platform,minimum,sdk=struct.unpack(endian+'III',data[:12]);out.append(dict(cpu=hex(cpu),platform=platform,minos=version(minimum),sdk=version(sdk)))
  elif cmd==0x24:
   minimum,sdk=struct.unpack(endian+'II',data[:8]);out.append(dict(cpu=hex(cpu),platform=1,minos=version(minimum),sdk=version(sdk)))
  if sz<8:break
  pos+=sz
 return out or [dict(cpu=hex(cpu),platform=1,minos=None,sdk=None)]
def audit(root, minimum):
 records.clear()
 for p in root.rglob('*'):
  if p.is_file() and not p.is_symlink():
   with p.open('rb') as f:r=inspect(f)
   for x in r:records.append(dict(path=str(p.relative_to(root)),**x))
 if not records:raise ValueError('No Mach-O code found in '+str(root))
 def parts(v):return tuple(map(int,(v+'.0.0').split('.')[:3]))
 for record in records:
  if record['platform'] != 1 or record['cpu'] != '0x100000c':
   raise ValueError('Not an Apple Silicon macOS binary: '+record['path'])
  if not record['minos']:
   raise ValueError('Missing macOS load-command minimum: '+record['path'])
  if parts(record['minos']) > parts(minimum):
   raise ValueError(record['path']+' requires macOS '+record['minos']+', exceeding '+minimum)
 metadata=root/'Contents/Info.plist'
 if metadata.exists():
  info=plistlib.loads(metadata.read_bytes())
  if parts(info['LSMinimumSystemVersion']) != parts(minimum):
   raise ValueError('App LSMinimumSystemVersion differs from advertised '+minimum)
  for extension in (root/'Contents/PlugIns').glob('*.appex'):
   info=plistlib.loads((extension/'Contents/Info.plist').read_bytes())
   if parts(info['LSMinimumSystemVersion']) != parts(minimum):
    raise ValueError(extension.name+' has a different minimum OS')
 return dict(root=str(root),minimum=minimum,counts=dict(collections.Counter(r['minos'] for r in records)),records=records.copy())

if __name__ == '__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('root',type=Path)
 parser.add_argument('--minimum',default='26.4')
 parser.add_argument('--report',type=Path)
 args=parser.parse_args()
 try:
  result=audit(args.root,args.minimum)
  if args.report:args.report.write_text(json.dumps(result,indent=2)+'\n')
  print('PASS: '+str(len(result['records']))+' arm64 Mach-O binaries require macOS '+args.minimum+' or earlier; counts '+str(result['counts']))
 except (ValueError,OSError,struct.error,KeyError) as error:
  parser.exit(1,'Mac compatibility audit failed: '+str(error)+'\n')
