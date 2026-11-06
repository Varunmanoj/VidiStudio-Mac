"""Atomic Copy to translation with a stubbed SDK transport."""
import copy
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import language_results as lr


class CopyTranslationTests(unittest.TestCase):
    def setUp(self):
        self.p = dict(id='translate', schemaVersion=2, duration=10,
            transcript=[dict(id='t', start=0, end=1, text='Hello.', speaker='A')],
            summary='# Hello\n\nA door opens.', summaryOrigin='manual',
            cues=[dict(id='a', start=2, end=4, text='A door opens.', audio='audio-description/source.wav',
                audioText='A door opens.', audioEngine='system', audioVoice='old', audioError='old error')],
            undoStack=[[dict(id='old', start=2, end=4, text='Old source text')]])
        lr.migrate(self.p)
        self.before = copy.deepcopy(self.p)
        self.calls = []
        def generate(**kwargs):
            self.calls.append(kwargs)
            items = json.loads(kwargs['contents'])
            return SimpleNamespace(text=json.dumps(dict(translations=[dict(index=v['index'], text='अनुवाद: ' + v['text']) for v in items])))
        self.generate = Mock(side_effect=generate)
        self.client = SimpleNamespace(models=SimpleNamespace(generate_content=self.generate), close=Mock())
        self.core = SimpleNamespace(client_and_model=Mock(return_value=(self.client, 'test-model')),
                                    is_retryable_ai_error=lambda error: True, emit=Mock())
        self.request = dict(sourceLanguage='auto', targetLanguage='hi', kinds=['transcript', 'summary', 'descriptions'])

    def run_translation(self, request=None):
        return lr.copy_results(self.p, request or self.request,
            translator=lambda sources, source, target: lr.translate_payloads(sources, source, target, self.core))

    def test_translates_all_text_preserving_ids_timing_speakers_and_sources(self):
        made = self.run_translation()
        self.assertEqual(len(made), 3)
        for kind in self.request['kinds']:
            self.assertEqual(lr.active(self.p, kind, 'auto'), lr.active(self.before, kind, 'auto'))
            new = lr.active(self.p, kind, 'hi')
            self.assertEqual(new['origin'], 'ai')
            self.assertTrue(new['payload'][lr.PRIMARY[kind]])
        row = lr.active(self.p, 'transcript', 'hi')['payload']['transcript'][0]
        self.assertEqual((row['id'], row['start'], row['end'], row['speaker']), ('t', 0, 1, 'A'))
        self.assertEqual(row['text'], 'अनुवाद: Hello.')
        self.assertIn('# Hello', lr.active(self.p, 'summary', 'hi')['payload']['summary'])
        cue = lr.active(self.p, 'descriptions', 'hi')['payload']['cues'][0]
        self.assertFalse(any(k.startswith('audio') for k in cue))
        self.assertNotIn('undoStack', lr.active(self.p, 'descriptions', 'hi')['payload'])
        self.assertIn('audio-description/source.wav', lr.referenced_paths(self.p))
        self.assertNotIn('start', json.loads(self.calls[0]['contents'])[0])
        self.assertIn('Detect each source language', self.calls[0]['config']['system_instruction'])
        self.client.close.assert_called_once()

    def test_invalid_later_selection_never_calls_gemini(self):
        self.request['segmentIDs'] = {'descriptions': ['missing']}
        with self.assertRaises(ValueError): self.run_translation()
        self.assertEqual(self.p, self.before)
        self.core.client_and_model.assert_not_called()

    def test_auto_target_rejected_before_network(self):
        self.request['targetLanguage'] = 'auto'
        with self.assertRaisesRegex(ValueError, 'specific target'): self.run_translation()
        self.core.client_and_model.assert_not_called()
        self.assertEqual(self.p, self.before)

    def test_missing_or_duplicate_response_items_never_save_partial_results(self):
        invalid = [[], [dict(index=0, text='one')] * 3,
                   [dict(index=i, text=' ') for i in range(3)],
                   [dict(index=i + 5, text='wrong') for i in range(3)]]
        for rows in invalid:
            with self.subTest(rows=rows), patch.object(lr.time, 'sleep'):
                self.generate.side_effect = None
                self.generate.return_value = SimpleNamespace(text=json.dumps(dict(translations=rows)))
                with self.assertRaises(ValueError): self.run_translation()
                self.assertEqual(self.p, self.before)

    def test_later_batch_failure_keeps_every_source_and_existing_target(self):
        self.p['transcript'] = [dict(id=str(i), start=i, end=i + 0.5, text='Hello') for i in range(45)]
        lr.capture(self.p); before = copy.deepcopy(self.p)
        original = self.generate.side_effect
        def generate(**kwargs):
            if len(self.calls): raise RuntimeError('permanent request failure')
            return original(**kwargs)
        self.generate.side_effect = generate
        self.core.is_retryable_ai_error = lambda error: False
        with self.assertRaises(RuntimeError): self.run_translation()
        self.assertEqual(self.p, before)
        self.client.close.assert_called_once()

    def test_selected_segment_only_sends_that_text(self):
        self.request.update(kinds=['descriptions'], segmentIDs={'descriptions': ['a']})
        self.run_translation()
        items = json.loads(self.calls[0]['contents'])
        self.assertEqual([v['text'] for v in items], ['A door opens.'])
        self.assertNotIn('source.wav', self.calls[0]['contents'])

    def test_large_text_is_batched_without_losing_any_selected_item(self):
        self.p['summary'] = 'a word\n' * 4000
        lr.capture(self.p)
        self.run_translation()
        self.assertGreater(len(self.calls), 1)
        self.assertTrue(all(sum(len(v['text']) for v in json.loads(c['contents'])) <= 16000 for c in self.calls))
        self.assertEqual(sum(v['text'].count('a word') for c in self.calls for v in json.loads(c['contents'])), 4000)
        self.assertEqual(lr.active(self.p, 'summary', 'hi')['payload']['summary'].count('a word'), 4000)

    def test_existing_target_retained_and_translation_failure_never_falls_back_to_copy(self):
        existing = lr.record(self.p, 'summary', 'hi', dict(summary='Existing Hindi'))
        self.p['languageResults'].append(existing)
        self.p['activeResultIDs']['hi'] = {'summary': existing['id']}
        before = copy.deepcopy(self.p)
        self.core.client_and_model.side_effect = ValueError('Add a Gemini API key in Settings first.')
        with self.assertRaisesRegex(ValueError, 'API key'): self.run_translation()
        self.assertEqual(self.p, before)

    def test_real_engine_retry_policy_preserves_credential_failure(self):
        import vidistudio_engine as core
        self.generate.side_effect = ValueError('API_KEY_INVALID')
        with patch.object(core, 'client_and_model', return_value=(self.client, 'test-model')):
            with self.assertRaisesRegex(ValueError, 'API_KEY_INVALID'):
                lr.copy_results(self.p, self.request, translator=lambda sources, source, target: lr.translate_payloads(sources, source, target, core))
        self.assertEqual(self.p, self.before)
        self.assertEqual(self.generate.call_count, 1)
        self.client.close.assert_called_once()
