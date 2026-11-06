import sys
import struct
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "engine"))
import mov_accessibility as mov


def track(media):
    header = bytearray(84)
    header[3] = 3
    return mov.atom(b"trak", mov.atom(b"tkhd", header) + mov.atom(b"mdia", mov.atom(b"hdlr", bytes(8) + media + bytes(12))))


class MetadataTests(unittest.TestCase):
    def test_single_described_audio_and_descriptive_subtitles_are_tagged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mixed.mov"
            movie = track(b"vide") + track(b"soun") + track(b"sbtl") + track(b"sbtl")
            path.write_bytes(mov.atom(b"moov", movie) + mov.atom(b"mdat", b"MEDIA"))
            mov.finalize(path, described_audio_indices=(0,), described_subtitle_indices=(1,))
            result = path.read_bytes()
            updated = next(value for kind, value in mov.children(result) if kind == b"moov")
            self.assertEqual(updated.count(mov.DESCRIPTION), 2)
            self.assertEqual(updated.count(mov.TRANSCRIPT), 2)
            mov.finalize(path, described_audio_indices=(0,), described_subtitle_indices=(1,))
            self.assertEqual(path.read_bytes(), result)

    def test_tags_groups_and_media_offsets(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "export.mov"
            movie = track(b"vide") + track(b"soun") + track(b"soun") + track(b"sbtl")
            original = mov.atom(b"ftyp", b"qt  ") + mov.atom(b"moov", movie) + mov.atom(b"mdat", b"UNCHANGED MEDIA")
            path.write_bytes(original)
            mov.finalize(path)
            result = path.read_bytes()
            self.assertEqual(result.index(b"UNCHANGED MEDIA"), original.index(b"UNCHANGED MEDIA"))
            self.assertEqual(result.count(b"UNCHANGED MEDIA"), 1)
            self.assertEqual(result.count(mov.DESCRIPTION), 1)
            self.assertEqual(result.count(mov.TRANSCRIPT), 1)
            updated = next(value for kind, value in mov.children(result) if kind == b"moov")
            groups = []
            for kind, payload in mov.children(updated):
                if kind == b"trak":
                    header = next(value for child, value in mov.children(payload) if child == b"tkhd")
                    groups.append(struct.unpack_from(">h", header, 34)[0])
            self.assertEqual(groups, [0, 1, 1, 2])
            mov.finalize(path)
            self.assertEqual(path.read_bytes(), result)

    def test_invalid_input_is_unchanged(self):
        for contents in [b"bad", mov.atom(b"moov", track(b"soun")), struct.pack(">I4s", 0, b"mdat")]:
            with self.subTest(contents=contents), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "invalid.mov"
                path.write_bytes(contents)
                with self.assertRaises(ValueError): mov.finalize(path)
                self.assertEqual(path.read_bytes(), contents)

    def test_bad_nested_atom_is_rejected(self):
        with self.assertRaises(ValueError): list(mov.children(struct.pack(">I4s", 999, b"trak")))

    def test_multilingual_names_are_complete_idempotent_and_preserve_media(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'labels.mov'
            movie = track(b'vide')+track(b'soun')+track(b'soun')+track(b'soun')+track(b'sbtl')
            original = mov.atom(b'ftyp',b'qt  ')+mov.atom(b'moov',movie)+mov.atom(b'mdat',b'UNCHANGED MEDIA')
            path.write_bytes(original)
            names=['Original Audio','English - Audio Description','Chinese (Simplified) - Audio Description']
            captions=['Hindi AD Transcript']
            mov.finalize(path,(1,2),(0,),names,captions)
            result=path.read_bytes()
            self.assertEqual(result.index(b'UNCHANGED MEDIA'),original.index(b'UNCHANGED MEDIA'))
            header=next(v for k,v in mov.children(result) if k==b'moov')
            actual=[]
            for kind,payload in mov.children(header):
                if kind!=b'trak' or mov.track_type(payload) not in (b'soun',b'sbtl'):continue
                userdata=next(v for k,v in mov.children(payload) if k==b'udta')
                items=dict(mov.children(userdata))
                name=items[b'name'].decode();actual.append(name)
                length,locale=struct.unpack_from('>HH',items[b'\xa9nam'])
                self.assertEqual(items[b'\xa9nam'][4:4+length].decode(),name)
            self.assertEqual(actual,names+captions)
            mov.finalize(path,(1,2),(0,),names,captions)
            self.assertEqual(path.read_bytes(),result)
            with self.assertRaises(ValueError):mov.finalize(path,(1,2),(0,),['Wrong count'],captions)
            self.assertEqual(path.read_bytes(),result)
