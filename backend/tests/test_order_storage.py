import asyncio
import tempfile
import unittest
from pathlib import Path

from app.order_storage import MAX_DOCUMENT_BYTES, save_upload, storage_path


class MemoryUpload:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    async def read(self, count: int) -> bytes:
        chunk = self.data[self.offset:self.offset + count]
        self.offset += len(chunk)
        return chunk


class OrderStorageTests(unittest.TestCase):
    def test_upload_is_saved_under_opaque_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key, size, checksum = asyncio.run(save_upload(root, "ORD-000001", MemoryUpload(b"scan")))
            self.assertEqual(size, 4)
            self.assertEqual(storage_path(root, key).read_bytes(), b"scan")
            self.assertEqual(len(checksum), 64)
            self.assertEqual(list(root.rglob("*.part")), [])

    def test_invalid_key_is_rejected(self):
        with self.assertRaises(ValueError):
            storage_path(Path("data"), "../secrets")

    def test_oversized_upload_leaves_no_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                asyncio.run(save_upload(root, "ORD-000001", MemoryUpload(b"x" * (MAX_DOCUMENT_BYTES + 1))))
            self.assertEqual(list(root.rglob("*.*")), [])


if __name__ == "__main__":
    unittest.main()
