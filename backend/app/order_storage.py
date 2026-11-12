"""Private local object storage for order documents.

Only opaque keys generated here are accepted as paths. The original filename is
metadata and is never used to choose a filesystem location.
"""

import hashlib
import os
import re
import uuid
from pathlib import Path

MAX_DOCUMENT_BYTES = 20 * 1024 * 1024
KEY_PATTERN = re.compile(r"^ORD-[0-9]{6,}/[0-9a-f]{32}$")


def storage_path(root: Path, key: str) -> Path:
    if not KEY_PATTERN.fullmatch(key):
        raise ValueError("Invalid document storage key")
    return root / key


def new_storage_key(order_id: str) -> str:
    key = f"{order_id}/{uuid.uuid4().hex}"
    storage_path(Path("."), key)
    return key


async def save_upload(root: Path, order_id: str, upload) -> tuple[str, int, str]:
    key = new_storage_key(order_id)
    destination = storage_path(root, key)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".part")
    digest = hashlib.sha256()
    size = 0
    try:
        with temporary.open("xb") as output:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_DOCUMENT_BYTES:
                    raise ValueError("File exceeds 20 MB")
                output.write(chunk)
                digest.update(chunk)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return key, size, digest.hexdigest()


def copy_gridfs_file(root: Path, order_id: str, source) -> tuple[str, int, str]:
    key = new_storage_key(order_id)
    destination = storage_path(root, key)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".part")
    digest = hashlib.sha256()
    size = 0
    try:
        with temporary.open("xb") as output:
            while chunk := source.read(1024 * 1024):
                size += len(chunk)
                output.write(chunk)
                digest.update(chunk)
            output.flush()
            os.fsync(output.fileno())
        if size != source.length:
            raise IOError("GridFS length mismatch")
        os.replace(temporary, destination)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return key, size, digest.hexdigest()
