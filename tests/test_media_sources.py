import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'collect_media_sources', Path(__file__).resolve().parents[1] / 'script/collect_media_sources.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class MediaSourceTests(unittest.TestCase):
    def test_git_source_does_not_borrow_a_resource_checksum(self):
        commit = '1' * 40
        checksum = '2' * 64
        recipe = f'''class Example < Formula
  url "https://example.com/library.git",
      revision: "{commit}"
  head "https://example.com/library.git", branch: "main"
  resource "data" do
    url "https://example.com/data.tar.xz"
    sha256 "{checksum}"
  end
end
'''
        self.assertEqual(collector.source_inputs(recipe), [
            {'url': 'https://example.com/library.git', 'revision': commit},
            {'url': 'https://example.com/data.tar.xz', 'sha256': checksum}])

    def test_unpinned_livecheck_url_is_not_treated_as_source(self):
        recipe = '''class Example < Formula
  livecheck do
    url "https://example.com/downloads.html"
  end
  resource "source" do
    url "https://example.com/source.tar.gz"
    sha256 "''' + 'a' * 64 + '''"
  end
end
'''
        self.assertEqual(len(collector.source_inputs(recipe)), 1)
        self.assertEqual(collector.source_inputs(recipe)[0]['url'], 'https://example.com/source.tar.gz')

    def test_changed_upstream_archive_is_rejected(self):
        def download(arguments, **kwargs):
            Path(arguments[arguments.index('--output') + 1]).write_bytes(b'changed upstream source')

        with tempfile.TemporaryDirectory() as folder, patch.object(collector.subprocess, 'run', side_effect=download):
            result = collector.collect(dict(component='library-1.0', url='https://example.com/source.tar.gz',
                                            sha256='0' * 64), Path(folder))
            self.assertEqual(result['status'], 'missing')
            self.assertIn('SHA-256 differs', result['error'])
            self.assertNotIn('path', result)
            self.assertFalse(any(Path(folder).rglob('*.partial')))


if __name__ == '__main__':
    unittest.main()
