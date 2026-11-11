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
  Users      : create / delete users. Passwords are hidden; click the eye icon beside a password to show/hide it.
  Performance: Marketing team performance. Top performers (filter by year / month, Top 3 / 5 / 10 / everyone,
               rank by orders or clinics added), a Month-wise dashboard and a Year-wise dashboard.
               Each order and clinic is credited to the Marketing user who created it. Cancelled orders are
               listed separately and don't count as orders. Records made before this update have no date /
               username: orders are matched to a user by name, clinics show as "Unattributed".

CANCELLING ORDERS
  The Marketing team can cancel an order from its detail page ("Cancel order") until the clinician has approved
  the plan. After approval the button disappears, and the server also refuses the cancel (HTTP 409).
  Cancelled orders show a "Cancelled" status to Marketing, Clinical CAD and Admin, and are read-only.

STATUS BAR AND ISSUES
  When a stage has more than one issue, the status bar shows a single step with a "+" icon instead of adding
  a step per issue. Clicking it scrolls to the Issues section of the same page.

FILES
  db.json    = orders + clinics (created on first run, starts empty; delete it to reset)
  users.json = login accounts (created on first run with the admin account; delete it to reset)
  uploads/   = uploaded files (created automatically)

DEMO ONLY: passwords are stored in plain text in users.json (hidden in the Admin screen, but not encrypted).
