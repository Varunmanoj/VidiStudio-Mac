"""Gemini text output languages, verified against Google's documentation on 2026-11-05.

Source: https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/google-models#language_support
The model-list API does not report language capabilities. Speech recognition locales
are input hints, not output translation languages. Keep the catalogue in ai-defaults.json.
"""
import json
from functools import lru_cache
from pathlib import Path

@lru_cache(maxsize=1)
def options():
    return json.loads(Path(__file__).with_name('ai-defaults.json').read_text())['outputLanguageOptions']

def selected(cfg, stage):
    stage = {'youtube_transcript': 'transcript', 'text_rewrite': 'audio_descriptions'}.get(stage, stage)
    if stage not in ('transcript', 'summary', 'audio_descriptions'):
        return 'auto'
    saved = cfg.get('outputLanguages') or {}
    code = saved.get(stage, 'auto') if isinstance(saved, dict) else 'auto'
    if code != 'auto' and code not in options():
        raise ValueError('Choose a supported output language or Auto in Settings > Gemini API.')
    return code

def instruction(cfg, stage):
    code = selected(cfg, stage)
    if stage not in ('transcript', 'youtube_transcript', 'summary', 'audio_descriptions', 'text_rewrite'):
        return ''
    if code == 'auto':
        if stage in ('transcript', 'youtube_transcript'):
            return ''  # Existing verbatim prompts / speech-model auto detection already apply.
        if stage == 'text_rewrite':
            return 'Preserve the language of the supplied description.'
        return ('Output language: Auto. Detect the primary language from the video itself, '
                'using spoken dialogue and visible text as evidence, and write in that language. '
                'Do not choose a different language just because the supplied transcript or summary was translated. '
                'If no language can be determined, use English. Understand content in every source language.')
    task = ('Translate all spoken dialogue faithfully into this language in transcript text fields, '
            'including code-switched speech. Preserve source speech timing and speaker identities; '
            'do not invent dialogue or stretch timestamps to fit translated text. '
            if stage in ('transcript', 'youtube_transcript') else
            'Write all audience-facing prose in this language, including headings and descriptions of visible text. ')
    return (f'Output language: {options()[code]} ({code}). This explicit output-language choice takes precedence '
            'over any earlier instruction to preserve original language, write verbatim, or avoid translation. '
            + task + 'Preserve required JSON keys, IDs, numeric values, timestamps and output structure. '
            'Keep proper names accurate. Use the normal script for the selected language.')
