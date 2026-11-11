-- Run once against the alignflow database. Prototype passwords are stored as plain text.
CREATE TABLE IF NOT EXISTS users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR(30) NOT NULL UNIQUE,
    password TEXT NOT NULL,
    name TEXT NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'marketing', 'cad', 'lab', 'qc')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_key ON users (lower(username));

-- Change this password before the app is accessible to anyone else.
INSERT INTO users (username, password, name, role)
VALUES ('admin', 'admin', 'Admin', 'admin')
ON CONFLICT (username) DO NOTHING;
