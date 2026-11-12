"""Copy legacy GridFS order documents into private local storage.

Run from backend/: python migrate_gridfs_documents.py
Original GridFS bytes are retained. Re-running skips already migrated entries.
"""

from bson import ObjectId
from gridfs.errors import NoFile

from app.main import files, order_store, settings
from app.order_storage import copy_gridfs_file, storage_path


def migrate():
    migrated = 0
    failed = 0
    for order in order_store().find({"documents": {"$exists": True}}):
        for document in order.get("documents", []):
            if document.get("storage_key"):
                continue
            document_id = document["id"]
            key = None
            try:
                source = files.get(ObjectId(document_id))
                key, size, checksum = copy_gridfs_file(
                    settings.data_dir / "orders", order["order_id"], source)
                if size != document["size"]:
                    raise IOError("Order metadata size does not match GridFS")
                result = order_store().update_one(
                    {"_id": order["_id"], "documents": {"$elemMatch": {
                        "id": document_id, "storage_key": {"$exists": False}}}},
                    {"$set": {"documents.$.storage_key": key,
                              "documents.$.sha256": checksum}})
                if result.modified_count != 1:
                    storage_path(settings.data_dir / "orders", key).unlink(missing_ok=True)
                    continue
                migrated += 1
                print(f"Migrated {order['order_id']} / {document_id}: {size} bytes")
            except (NoFile, ValueError, OSError, KeyError) as exc:
                if key:
                    storage_path(settings.data_dir / "orders", key).unlink(missing_ok=True)
                failed += 1
                print(f"FAILED {order['order_id']} / {document_id}: {exc}")
    print(f"Complete: {migrated} migrated, {failed} failed. GridFS originals retained.")
    return failed


if __name__ == "__main__":
    raise SystemExit(1 if migrate() else 0)
