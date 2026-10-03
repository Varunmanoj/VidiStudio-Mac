"""Copy Homebrew media binaries and relocate their non-system dylibs."""
import os, re, shutil, subprocess, sys, json
from pathlib import Path
out=Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
seen={}
def deps(path):
    return [line.strip().split(' (compatibility')[0] for line in subprocess.check_output(['otool','-L',str(path)],text=True).splitlines()[1:]]
def copy(path):
    source=Path(path).resolve()
    if source in seen: return seen[source]
    target=out/source.name
    if target.exists() and source not in seen: target.unlink()
    shutil.copy2(source,target); target.chmod(0o755); seen[source]=target
    subprocess.run(['codesign','--remove-signature',str(target)],capture_output=True)
    for dep in deps(source):
        if dep.startswith('/opt/homebrew/') or dep.startswith('/usr/local/'):
            child=copy(dep)
            subprocess.run(['install_name_tool','-change',dep,'@loader_path/'+child.name,str(target)],check=True,capture_output=True)
        elif dep.startswith('@'):
            candidate=source.parent/dep.replace('@loader_path/','').replace('@rpath/','')
            if not candidate.exists(): raise RuntimeError('Unresolved dependency '+dep+' in '+str(source))
            child=copy(candidate)
            subprocess.run(['install_name_tool','-change',dep,'@loader_path/'+child.name,str(target)],check=True,capture_output=True)
    if '.dylib' in target.name:
        subprocess.run(['install_name_tool','-id','@loader_path/'+target.name,str(target)],check=True,capture_output=True)
    subprocess.run(['codesign','--force','--sign','-',str(target)],check=True,capture_output=True)
    return target
for name in ['ffmpeg','ffprobe']:
    full=Path('/opt/homebrew/opt/ffmpeg-full/bin')/name
    binary=str(full) if full.is_file() else shutil.which(name)
    if not binary: raise RuntimeError(name+' missing')
    copy(binary)
from deno._find_deno import find_deno_bin
copy(find_deno_bin())
for target in seen.values():
    if any(d.startswith(('/opt/homebrew/','/usr/local/')) for d in deps(target)): raise RuntimeError('Nonportable dependency '+str(target))
print('Bundled',len(seen),'media binaries and libraries')

licenses=out.parent/'licenses'; licenses.mkdir(exist_ok=True)
provenance=[]
for source in seen:
    parts=source.parts
    if 'Cellar' in parts:
        idx=parts.index('Cellar'); formula=parts[idx+1]; version=parts[idx+2]
        prefix=Path(*parts[:idx+3]); destination=licenses/(formula+'-'+version); destination.mkdir(exist_ok=True)
        provenance.append(dict(formula=formula,version=version,binary=source.name))
        for item in prefix.iterdir():
            if item.is_file() and any(word in item.name.upper() for word in ['LICENSE','COPYING','NOTICE','AUTHORS']):
                shutil.copy2(item,destination/item.name)
(licenses/'media-provenance.json').write_text(json.dumps(provenance,indent=2))
