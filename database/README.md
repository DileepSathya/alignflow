# One-time setup on local PostgreSQL

PostgreSQL 17 is installed locally and listens on `localhost:5432`. Create a database named `alignflow` in pgAdmin, then open its Query Tool and run the contents of `setup.sql` once.

Or run these commands from the project root in PowerShell (enter your PostgreSQL password when prompted):

```powershell
& 'C:\Program Files\PostgreSQL\17\bin\createdb.exe' -h localhost -U postgres -W alignflow
& 'C:\Program Files\PostgreSQL\17\bin\psql.exe' -h localhost -U postgres -W -d alignflow -f database/setup.sql
```

The script creates the `users`, `sessions`, and `clinics` tables and seeds `admin` / `admin`. It is safe to rerun if needed. Run it again on an existing database to add the clinics table. Change the seeded password immediately for any shared environment. The API does not create or migrate tables at startup.

## Orders: MongoDB

Orders and their uploaded documents use MongoDB. Install and run MongoDB locally, or supply a MongoDB connection string through the API environment:

```text
MONGODB_URL=mongodb://localhost:27017
MONGODB_DATABASE=alignflow
```

The backend creates unique indexes on `order_id` and `request_id` when an order endpoint is first used. A MongoDB counter atomically assigns display IDs such as `ORD-000001`; gaps are possible if a submission fails after reserving a number. The underlying MongoDB `_id` remains the internal identifier. New uploads are saved under the private `data/orders/` directory; MongoDB stores document metadata and SHA-256 checksums. Downloads still go through the authenticated API. Set `DATA_DIR` in `backend/.env` to move the storage root. Back up MongoDB and `data/orders/` together. Existing demo `db.json` orders are not automatically imported.

To copy existing GridFS files into `data/orders/`, run `backend/.venv312/Scripts/python.exe migrate_gridfs_documents.py` from the `backend` directory. The script verifies file length, records each new storage key and checksum, and can be rerun safely. It retains GridFS originals for rollback. Confirm downloads and backups before removing any originals manually.

For local development, `run_application.bat` starts a MongoDB process bound to `127.0.0.1` when nothing is listening on port 27017. Its data lives in ignored `.local/mongodb/data`. This local instance has no MongoDB authentication and must stay bound to loopback. The API still uses PostgreSQL authentication and role checks. If `MONGODB_URL` is set in `backend/.env`, the launcher leaves MongoDB startup to that connection instead.

For a shared or production deployment, run an authenticated MongoDB service and set `MONGODB_URL` to an account with read/write and index creation permissions for the `alignflow` database, for example `mongodb://USERNAME:PASSWORD@localhost:27017/alignflow?authSource=admin` (URL encode special characters in the password). Keep credentials in `backend/.env`; do not commit that file. The separately installed Windows service named `MongoDB` is configured with authentication and uses its own data directory. The development launcher does not alter that service or its data.
