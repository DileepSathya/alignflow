-- Run once against the alignflow database. Prototype passwords are stored as plain text.
CREATE TABLE IF NOT EXISTS users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR(30) NOT NULL UNIQUE,
    password TEXT NOT NULL,
    name TEXT NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'marketing', 'scanner', 'planning', 'production', 'clinic_admin', 'clinician')),
    clinic_id BIGINT,
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
    contact_number TEXT NOT NULL,
    email TEXT,
    area TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    signup_source TEXT NOT NULL DEFAULT 'marketing',
    approval_status TEXT NOT NULL DEFAULT 'approved',
    reviewed_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT
);

ALTER TABLE clinics ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS clinics_created_by_idx ON clinics (created_by);
DO $$ BEGIN
    ALTER TABLE users ADD CONSTRAINT users_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES clinics(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS clinicians (
    clinician_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL,
    mobile_number TEXT NOT NULL,
    email TEXT,
    clinic_id BIGINT NOT NULL REFERENCES clinics(id) ON DELETE CASCADE,
    clinical_role TEXT NOT NULL DEFAULT 'doctor',
    added_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    account_id BIGINT UNIQUE REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS clinicians_clinic_id_idx ON clinicians (clinic_id);

CREATE TABLE IF NOT EXISTS patients (
    patient_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    clinic_patient_id VARCHAR(100),
    name VARCHAR(160) NOT NULL,
    mobile_number VARCHAR(30) NOT NULL,
    email TEXT,
    clinic_id BIGINT NOT NULL REFERENCES clinics(id),
    clinician_id BIGINT REFERENCES clinicians(clinician_id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (clinic_id, clinic_patient_id)
);
CREATE INDEX IF NOT EXISTS patients_clinic_id_idx ON patients (clinic_id);

CREATE TABLE IF NOT EXISTS patient_orders (
    order_id VARCHAR(30) PRIMARY KEY,
    patient_id BIGINT NOT NULL REFERENCES patients(patient_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS patient_orders_patient_id_idx ON patient_orders (patient_id);

-- Existing clinics stored the dentist only in the clinics table.
ALTER TABLE clinics ADD COLUMN IF NOT EXISTS dentist_name TEXT;
INSERT INTO clinicians (name, mobile_number, email, clinic_id)
SELECT c.dentist_name, c.contact_number, c.email, c.id
FROM clinics c
WHERE c.dentist_name IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM clinicians p
    WHERE p.clinic_id = c.id AND p.name = c.dentist_name
      AND p.mobile_number = c.contact_number
);
ALTER TABLE clinics DROP COLUMN IF EXISTS dentist_name;

-- Change this password before the app is accessible to anyone else.
INSERT INTO users (username, password, name, role)
VALUES ('admin', 'admin', 'Admin', 'admin')
ON CONFLICT (username) DO NOTHING;
