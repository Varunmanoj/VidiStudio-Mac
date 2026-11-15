"""Refresh the bundled, credential-free Sarvam voice catalog from official documentation."""
import html
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://docs.sarvam.ai/api/api-guides-tutorials/text-to-speech/voices'

def fetch(url):
    return subprocess.check_output(['curl', '-fsSL', '--max-time', '60', url]).decode()

def main():
    markdown, page = fetch(URL + '.md'), fetch(URL)
    languages = {'bn-IN':'Bengali', 'en-IN':'English (India)', 'gu-IN':'Gujarati', 'hi-IN':'Hindi',
                 'kn-IN':'Kannada', 'ml-IN':'Malayalam', 'mr-IN':'Marathi', 'od-IN':'Odia',
                 'pa-IN':'Punjabi', 'ta-IN':'Tamil', 'te-IN':'Telugu'}
    demos = {}
    for path in re.findall(r'<audio[^>]+src="([^"]+)"', page):
        path = html.unescape(path)
        if '/v3/' in path:
            demos[path.rsplit('/', 1)[-1].split('.')[0]] = 'https://docs.sarvam.ai' + path if path.startswith('/') else path
    voices = []
    for identifier, name, style in re.findall(r'\|\s*`([^`]+)`\s*\|\s*([^|]+)\|\s*([^|]+)\|', markdown):
        if '_' not in identifier: continue
        tag = identifier.split('_')[1]
        codes = ['en-IN', 'hi-IN'] if tag == 'enhi' else [tag + '-IN']
        voices.append(dict(id=identifier, name=name.strip(), style=style.strip(), model='bulbul:v4-flash', languages=codes))
    v3 = 'shubh aditya ritu priya neha rahul pooja rohan simran kavya amit dev ishita shreya ratan varun manan sumit roopa kabir aayan ashutosh advait anand tanya tarun sunny mani gokul vijay shruti suhani mohit kavitha rehan soham rupali'.split()
    for model, names in [('bulbul:v3', v3), ('bulbul:v2', 'anushka manisha vidya arya abhilash karun hitesh'.split())]:
        for identifier in names:
            voice = dict(id=identifier, name=identifier.title(), style='', model=model, languages=list(languages))
            if model == 'bulbul:v3' and identifier in demos: voice['demoUrl'] = demos[identifier]
            voices.append(voice)
    assert len([v for v in voices if v['model'] == 'bulbul:v4-flash']) >= 200
    assert len(demos) == 37
    catalog = json.dumps(dict(source=URL, languages=languages, voices=voices), ensure_ascii=False, indent=2) + '\n'
    for root in [ROOT, ROOT.parent / 'Vidi-Studio-Windows']:
        (root / 'engine/sarvam-voices.json').write_text(catalog)
    print(f'Bundled {len(voices)} voices and {len(demos)} published demos.')

if __name__ == '__main__': main()
