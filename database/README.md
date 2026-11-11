# One-time setup on local PostgreSQL

PostgreSQL 17 is installed locally and listens on `localhost:5432`. Create a database named `alignflow` in pgAdmin, then open its Query Tool and run the contents of `setup.sql` once.

Or run these commands from the project root in PowerShell (enter your PostgreSQL password when prompted):

```powershell
& 'C:\Program Files\PostgreSQL\17\bin\createdb.exe' -h localhost -U postgres -W alignflow
& 'C:\Program Files\PostgreSQL\17\bin\psql.exe' -h localhost -U postgres -W -d alignflow -f database/setup.sql
```

The script creates the `users` and `sessions` tables and seeds `admin` / `admin`. It is safe to rerun if needed. Change the seeded password immediately for any shared environment. The API does not create or migrate tables at startup.
