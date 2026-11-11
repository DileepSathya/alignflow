V Clear demo (AlignFlow)
1. Install Node.js (v18+)
2. In this folder run:  node server.js
3. Open http://localhost:3000  -> you land on the Login page

LOGIN
  admin / admin  (role: admin) is created automatically on first run.
  Log in as admin -> Users -> "Create user" to add people for each team:
  Marketing, Clinical CAD, Lab / Manufacturing, QC (name, username, password, role).
  Each person then logs in and is taken to their own team page.
  Each browser TAB keeps its own login, so open one tab per user to demo the hand-offs.

ADMIN PAGE (admin.html)
  All orders : every order with stage statuses, who handled each stage, patient + clinic details,
               documents, comments and issues (read-only, refreshes live).
  Users      : create / delete users.

FILES
  db.json    = orders + clinics (created on first run, starts empty; delete it to reset)
  users.json = login accounts (created on first run with the admin account; delete it to reset)
  uploads/   = uploaded files (created automatically)

DEMO ONLY: passwords are stored and shown in plain text, no encryption.
