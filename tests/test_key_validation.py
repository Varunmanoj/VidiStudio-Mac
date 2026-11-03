"""Credential verdicts must come from Google, independently of network failures."""
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from test_engine import engine


class KeyValidation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'config.json'
        self.cfg = {'apiKey': 'test-key-for-mocked-service', 'apiKeyValid': True,
                    'apiPlan': 'paid', 'geminiPlan': 'paid', 'models': {'summary': 'saved-choice'}}
        self.path.write_text(json.dumps(self.cfg))
        self.original = self.path.read_bytes()
        self.environment = patch.dict(os.environ, {'VIDISTUDIO_CONFIG': str(self.path)})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def check(self, client):
        output = io.StringIO()
        with patch.object(engine, 'config', return_value=self.cfg), \
             patch.object(engine, 'gemini_client', return_value=client), redirect_stdout(output):
            engine.check_api_key()
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def test_empty_or_whitespace_key_never_contacts_google_or_marks_invalid(self):
        for key in ['', '  \n\t']:
            with self.subTest(key=repr(key)):
                self.cfg['apiKey'] = key
                with patch.object(engine, 'gemini_client') as client:
                    events = self.check(client)
                client.models.list.assert_not_called()
                self.assertEqual(events[-1]['keyStatus'], 'missing')
                self.assertNotIn('keyValid', events[-1])
                self.assertEqual(self.path.read_bytes(), self.original)

    def test_explicit_rejection_reports_invalid_and_never_success(self):
        client = Mock()
        client.models.list.side_effect = ValueError('400 API_KEY_INVALID: API key not valid')
        events = self.check(client)
        self.assertEqual(events[-1]['keyStatus'], 'invalid')
        self.assertIs(events[-1]['keyValid'], False)
        self.assertIn('entered Gemini API key is invalid', events[-1]['validationMessage'])
        self.assertFalse(any(e.get('keyValid') is True for e in events))
        self.assertNotIn(self.cfg['apiKey'], json.dumps(events))
        client.close.assert_called_once()

    def test_structured_credential_rejection_is_recognized(self):
        error = ValueError('Google rejected the request')
        error.details = [{'reason': 'API_KEY_INVALID'}]
        client = Mock()
        client.models.list.side_effect = error
        events = self.check(client)
        self.assertEqual(events[-1]['keyStatus'], 'invalid')
        self.assertIs(events[-1]['keyValid'], False)

    def test_success_verifies_the_entered_key_and_returns_real_catalog(self):
        client = Mock()
        client.models.list.return_value = [SimpleNamespace(name='models/gemini-test',
            display_name='Test Model', supported_actions=['generateContent'])]
        events = self.check(client)
        self.assertEqual(events[-1]['keyStatus'], 'valid')
        self.assertIs(events[-1]['keyValid'], True)
        self.assertEqual([m['name'] for m in events[-1]['models']], ['gemini-test'])
        client.close.assert_called_once()

    def test_connection_quota_permission_and_service_failures_preserve_verification(self):
        for error in [ConnectionError('offline'), TimeoutError('timeout'),
                      ValueError('429 RESOURCE_EXHAUSTED quota'),
                      ValueError('403 PERMISSION_DENIED restriction'), ValueError('503 unavailable')]:
            with self.subTest(error=error):
                client = Mock()
                client.models.list.side_effect = error
                with self.assertRaises(type(error)):
                    self.check(client)
                self.assertEqual(self.path.read_bytes(), self.original)
                client.close.assert_called_once()

    def test_empty_compatible_catalog_is_not_an_invalid_key(self):
        client = Mock()
        client.models.list.return_value = []
        with self.assertRaisesRegex(ValueError, 'No compatible Gemini models'):
            self.check(client)
        self.assertEqual(self.path.read_bytes(), self.original)


if __name__ == '__main__':
    unittest.main()
