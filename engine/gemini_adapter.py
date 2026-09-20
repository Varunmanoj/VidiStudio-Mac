"""Shared Gemini contracts; no credentials, defaults or storage ownership here."""
import math, time
from pathlib import Path

MAX_FILE_SIZE_BYTES = 2_000_000_000
FILE_SIZE_ERROR = ('VidiStudio supports files up to 2 GB for Gemini processing. '
                   'Choose a smaller video or create a YouTube project instead.')

def value(obj,key,default=None):
    return obj.get(key,default) if isinstance(obj,dict) else getattr(obj,key,default)

def output_text(result):
    direct=value(result,'output_text')
    if direct: return direct
    texts=[]
    for step in value(result,'steps',[]) or []:
        if value(step,'type')=='model_output':
            texts.extend(value(c,'text','') for c in value(step,'content',[]) or [] if value(c,'type')=='text')
    return '\n'.join(texts)

def ready_file(client,path,emit=lambda *_:None):
    if Path(path).stat().st_size > MAX_FILE_SIZE_BYTES:
        raise ValueError(FILE_SIZE_ERROR)
    f=client.files.upload(file=str(path)); deadline=time.monotonic()+900
    try:
        while str(value(value(f,'state'),'name',value(f,'state'))).upper()=='PROCESSING':
            if time.monotonic()>deadline: raise TimeoutError('Gemini file preparation timed out.')
            emit('Preparing the video for analysis'); time.sleep(2); f=client.files.get(name=f.name)
        if str(value(value(f,'state'),'name',value(f,'state'))).upper()!='ACTIVE': raise ValueError('Gemini rejected this media file.')
        return f
    except BaseException:
        try: client.files.delete(name=f.name)
        except Exception: pass
        raise

def seconds(raw):
    if isinstance(raw,str): raw=raw.removesuffix('s')
    number=float(raw)
    if not math.isfinite(number): raise ValueError('Non-finite transcript timestamp.')
    return number

def speech_segments(result, offset=0):
    words=[]
    for step in value(result,'steps',[]) or []:
        for content in value(step,'content',[]) or []:
            for word in value(content,'annotations',[]) or []:
                if value(word,'type')=='word_info':
                    a=seconds(value(word,'start_offset')); b=seconds(value(word,'end_offset'))
                    if a<0 or b<a: raise ValueError('Invalid word annotation timing.')
                    words.append(dict(start=a+offset,end=b+offset,text=value(word,'text',''),speaker=value(word,'speaker','')))
    words.sort(key=lambda w:w['start'])
    if not words:
        raise ValueError('Transcription returned no word timestamps. No existing transcript was replaced. Check model/API availability or choose a video model for transcription.')
    segments=[]
    for word in words:
        if segments and word['speaker']==segments[-1].get('speaker') and word['start']-segments[-1]['end']<.7 and word['end']-segments[-1]['start']<=7:
            segments[-1]['text']+=' '+word['text'];segments[-1]['end']=word['end']
        else: segments.append(word.copy())
    return segments

def transcribe_audio(client,model,path,offset=0,emit=lambda *_:None):
    f=ready_file(client,path,emit)
    try:
        result=client.interactions.create(model=model,input=[{'type':'audio','uri':f.uri,'mime_type':f.mime_type}],generation_config={'transcription_config':{'language_codes':[],'mode':{'type':'verbatim','timestamp_granularities':['word'],'diarization_mode':'speaker'}}})
        return speech_segments(result,offset)
    finally:
        try: client.files.delete(name=f.name)
        except Exception: emit('Finishing narration preparation')

def video_interaction(client,model,uri,mime,prompt,system='',schema=None,processing='agentic'):
    media={'type':'video','uri':uri}
    if mime: media['mime_type']=mime
    if processing: media['processing']=processing
    args=dict(model=model,input=[media,{'type':'text','text':prompt}])
    if system: args['system_instruction']=system
    if schema: args['response_format']={'type':'text','mime_type':'application/json','schema':schema}
    result=client.interactions.create(**args)
    text=output_text(result)
    if not text: raise ValueError('Gemini returned no text; existing results were preserved.')
    return text
