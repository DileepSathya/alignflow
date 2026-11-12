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

CREATE TABLE IF NOT EXISTS clinics (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    clinic_name TEXT NOT NULL,
    dentist_name TEXT NOT NULL,
    contact_number TEXT NOT NULL,
    email TEXT,
    area TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE clinics ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS clinics_created_by_idx ON clinics (created_by);

-- Change this password before the app is accessible to anyone else.
INSERT INTO users (username, password, name, role)
VALUES ('admin', 'admin', 'Admin', 'admin')
ON CONFLICT (username) DO NOTHING;
