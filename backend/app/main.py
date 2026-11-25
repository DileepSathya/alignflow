from datetime import datetime, timedelta, timezone
import secrets
import hashlib
import hmac
from pathlib import Path
from typing import Literal

import psycopg
from psycopg.rows import dict_row
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from pymongo import MongoClient, ReturnDocument, ASCENDING, DESCENDING
from pymongo.errors import DuplicateKeyError
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure
from bson import ObjectId
from fastapi import File, UploadFile, Form
from copy import deepcopy
from fastapi.responses import StreamingResponse, FileResponse
from fastapi.responses import JSONResponse
from gridfs import GridFS
from urllib.parse import quote
import yaml
from app.order_storage import save_upload, storage_path


class Settings(BaseSettings):
    database_url: str
    mongodb_url: str = "mongodb://localhost:27017"
    mongodb_database: str = "alignflow"
    data_dir: Path = Path(__file__).resolve().parents[2] / "data"
    cors_origins: str = "http://localhost:8080,http://127.0.0.1:8080"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
TEAM_CONFIG_PATH = Path(__file__).resolve().parents[1] / "config.yaml"
CONFIG = yaml.safe_load(TEAM_CONFIG_PATH.read_text(encoding="utf-8"))
SCANNER_CHECKLIST = CONFIG["scanner_checklist"]


def load_teams():
    teams = CONFIG["teams"]
    ids = [team["id"] for team in teams]
    if set(ids) != {"marketing", "scanner", "planning", "production"} or len(ids) != 4 or any(
        not isinstance(team.get("id"), str) or not isinstance(team.get("labels"), str)
        or not team["id"] or not team["labels"].strip() or team["id"] == "admin"
        for team in teams
    ):
        raise ValueError("Invalid config.yaml teams")
    return teams


TEAMS = load_teams()
CLINIC_ROLES = {"clinic_admin", "clinician"}
CLINICAL_REVIEW_ROLES = {"admin", "marketing"} | CLINIC_ROLES
QC_REVIEW_ROLES = {"admin", "production", "planning"}
TEAM_IDS = {team["id"] for team in TEAMS}
mongo = MongoClient(settings.mongodb_url, serverSelectionTimeoutMS=3000)[settings.mongodb_database]
orders = mongo.orders
files = GridFS(mongo)
_orders_indexed = False


def order_store():
    global _orders_indexed
    if not _orders_indexed:
        orders.create_index("order_id", unique=True)
        orders.create_index("request_id", unique=True, sparse=True)
        orders.create_index([("created_at", DESCENDING)])
        orders.create_index([("status", ASCENDING), ("created_at", DESCENDING)])
        for order in orders.find({"issues": {"$not": {"$elemMatch": {"resolved_at": None}}}, "independent_batches": {"$ne": True}, "batches.status": {"$in": ["manufactured", "qc_issues"]}},
                                 {"status": 1, "batches": 1, "current_batch": 1, "assigned_planner": 1}):
            fields = sequential_batch_fields(order, deepcopy(order["batches"]))
            if any(order.get(key) != value for key, value in fields.items()):
                orders.update_one({"_id": order["_id"], "batches": order["batches"],
                                   "status": order["status"]}, {"$set": fields})
        for held in orders.find({"independent_batches": True, "issues": {"$elemMatch": {"resolved_at": None}}}):
            numbers = [i["batch_number"] for i in held["issues"] if i.get("resolved_at") is None and i.get("batch_number")]
            if numbers:
                orders.update_one({"_id": held["_id"], "issue_revision": held.get("issue_revision"), "batches": held["batches"]},
                                  {"$set": {"status": "issue_raised", "current_batch": min(numbers)}})
        orders.update_many({"status": "submitted", "assigned_planner": None,
                            "scanner_approved": {"$ne": True}},
                           {"$set": {"status": "scanner_review", "checklist": new_checklist(),
                                     "updated_at": now()}})
        _orders_indexed = True
    return orders


app = FastAPI(title="V-Clear Aligners API")


@app.exception_handler(ServerSelectionTimeoutError)
def mongodb_unavailable(request, exc):
    return JSONResponse(status_code=503, content={"detail":
        "Orders database is unavailable. Start MongoDB and check MONGODB_URL."})


@app.exception_handler(OperationFailure)
def mongodb_operation_failed(request, exc):
    if exc.code in {13, 18}:
        return JSONResponse(status_code=503, content={"detail":
            "Orders database authentication failed. Check MONGODB_URL credentials."})
    return JSONResponse(status_code=503, content={"detail": "Orders database operation failed."})
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)


def connection():
    with psycopg.connect(settings.database_url, row_factory=dict_row) as conn:
        yield conn


@app.on_event("startup")
def migrate_clinic_attribution():
    # Existing installations created clinics before the Marketing owner was stored.
    with psycopg.connect(settings.database_url) as conn:
        with conn.cursor() as cur:
            cur.execute("ALTER TABLE clinics ADD COLUMN IF NOT EXISTS created_by BIGINT "
                        "REFERENCES users(id) ON DELETE SET NULL")
            cur.execute("CREATE INDEX IF NOT EXISTS clinics_created_by_idx ON clinics (created_by)")
            cur.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check")
            cur.execute("ALTER TABLE clinics ADD COLUMN IF NOT EXISTS signup_source TEXT NOT NULL DEFAULT 'marketing'")
            cur.execute("ALTER TABLE clinics ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved'")
            cur.execute("ALTER TABLE clinics ADD COLUMN IF NOT EXISTS reviewed_by BIGINT REFERENCES users(id) ON DELETE SET NULL")
            cur.execute("ALTER TABLE clinics ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ")
            cur.execute("ALTER TABLE clinics ADD COLUMN IF NOT EXISTS rejection_reason TEXT")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS clinic_id BIGINT REFERENCES clinics(id) ON DELETE CASCADE")
            cur.execute("ALTER TABLE clinicians ADD COLUMN IF NOT EXISTS clinical_role TEXT NOT NULL DEFAULT 'doctor'")
            cur.execute("ALTER TABLE clinicians ADD COLUMN IF NOT EXISTS added_by BIGINT REFERENCES users(id) ON DELETE SET NULL")
            cur.execute("ALTER TABLE clinicians ADD COLUMN IF NOT EXISTS account_id BIGINT UNIQUE REFERENCES users(id) ON DELETE SET NULL")
            cur.execute("UPDATE users SET role = CASE role "
                        "WHEN 'cad' THEN 'planning' WHEN 'lab' THEN 'production' "
                        "WHEN 'qc' THEN 'planning' ELSE role END "
                        "WHERE role IN ('cad', 'lab', 'qc')")
            cur.execute("ALTER TABLE users ADD CONSTRAINT users_role_check "
                        "CHECK (role IN ('admin', 'marketing', 'scanner', 'planning', 'production', 'clinic_admin', 'clinician'))")


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, 200000)
    return f'pbkdf2${salt.hex()}${digest.hex()}'


def verify_password(password: str, stored: str) -> bool:
    if not stored.startswith('pbkdf2$'):
        return hmac.compare_digest(password, stored)
    try:
        _, salt, digest = stored.split('$')
        actual = hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 200000)
        return hmac.compare_digest(actual, bytes.fromhex(digest))
    except ValueError:
        return False


class LoginInput(BaseModel):
    username: str
    password: str


class ClinicSignup(BaseModel):
    clinic_name: str = Field(min_length=1)
    contact_number: str = Field(min_length=1)
    email: str = Field(min_length=3)
    area: str = Field(min_length=1)
    clinician_name: str = Field(min_length=1)
    clinician_mobile: str = Field(min_length=1)
    clinician_email: str = Field(min_length=3)
    clinical_role: str = Field(min_length=1)
    username: str = Field(pattern=r'^[A-Za-z0-9._-]{2,30}$')
    password: str = Field(min_length=8)


class UserInput(BaseModel):
    name: str = Field(min_length=1)
    username: str = Field(pattern=r"^[A-Za-z0-9._-]{2,30}$")
    password: str = Field(min_length=1)
    role: str

    @field_validator("name", "username")
    @classmethod
    def strip_value(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field is required")
        return value

    @field_validator("role")
    @classmethod
    def valid_role(cls, value: str) -> str:
        if value not in TEAM_IDS:
            raise ValueError("Choose a valid team role")
        return value


class UserUpdate(UserInput):
    password: str | None = None


class ClinicianInput(BaseModel):
    username: str | None = Field(default=None, max_length=30)
    password: str | None = Field(default=None, min_length=8, repr=False)
    clinician_id: int | None = None
    name: str = Field(min_length=1)
    mobile_number: str = Field(min_length=1)
    email: str | None = None
    clinical_role: str = 'doctor'

    @field_validator("name", "mobile_number")
    @classmethod
    def required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field is required")
        return value

    @field_validator("email")
    @classmethod
    def optional_email(cls, value: str | None) -> str | None:
        value = value.strip() if value else None
        if value and ("@" not in value or "." not in value.split("@")[-1]):
            raise ValueError("Enter a valid email address")
        return value or None


class ClinicInput(BaseModel):
    clinic_name: str = Field(min_length=1)
    contact_number: str = Field(min_length=1)
    email: str | None = None
    area: str = Field(min_length=1)
    clinicians: list[ClinicianInput] | None = None
    admin_username: str | None = None
    admin_password: str | None = None

    @field_validator("clinic_name", "contact_number", "area")
    @classmethod
    def required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field is required")
        return value

    @field_validator("email")
    @classmethod
    def optional_email(cls, value: str | None) -> str | None:
        value = value.strip() if value else None
        if value and ("@" not in value or "." not in value.split("@")[-1]):
            raise ValueError("Enter a valid email address")
        return value or None

def public_user(user: dict) -> dict:
    return {key: user.get(key) for key in ("id", "username", "name", "role", "clinic_id", "created_at")}


def current_user(request: Request, authorization: str | None = Header(default=None), conn=Depends(connection)) -> dict:
    token = authorization.removeprefix("Bearer ") if authorization else ""
    if not token or token == authorization:
        raise HTTPException(status_code=401, detail="Not signed in")
    with conn.cursor() as cur:
        cur.execute(
            "SELECT u.* FROM users u JOIN sessions s ON s.user_id = u.id "
            "WHERE s.token = %s AND s.expires_at > NOW()",
            (token,),
        )
        user = cur.fetchone()
    if user is None:
        raise HTTPException(status_code=401, detail="Session expired")
    if user['role'] in CLINIC_ROLES:
        path = request.url.path
        allowed_get = path in {'/api/me', '/api/my-clinic', '/api/my-clinic/overview', '/api/orders', '/api/patients', '/api/scanner/checklist'} or path.startswith('/api/orders/')
        order_action = path.startswith('/api/orders/') and path.split('/')[-1] in {'issues', 'status', 'documents'}
        allowed_post = path in {'/api/logout', '/api/my-clinic/clinicians', '/api/orders'} or order_action
        route = request.scope.get("route")
        template = getattr(route, "path", "")
        issue_reply = request.method == "POST" and template in {
            "/api/orders/{order_id}/issues/{issue_id}/replies", "/api/orders/{order_id}/issues/{issue_id}/read",
            "/api/orders/{order_id}/issues/{issue_id}/resolve"}
        checklist_edit = request.method == "PUT" and template == "/api/orders/{order_id}/checklist/{item_id}"
        review_submit = request.method == "POST" and template == "/api/orders/{order_id}/document-review/submit"
        if not (checklist_edit or review_submit or issue_reply or (request.method == 'GET' and allowed_get) or (request.method == 'POST' and allowed_post)):
            raise HTTPException(status_code=403, detail='Clinic access is restricted')
        with conn.cursor() as cur:
            cur.execute('SELECT c.approval_status, p.clinician_id FROM clinics c LEFT JOIN clinicians p '
                        'ON p.clinic_id=c.id AND p.account_id=%s WHERE c.id=%s', (user['id'], user['clinic_id']))
            clinic = cur.fetchone()
        if clinic is None or clinic['approval_status'] != 'approved':
            raise HTTPException(status_code=403, detail='Clinic approval required')
        user["clinician_id"] = clinic.get("clinician_id")
        if user["role"] == "clinician" and (not user["clinician_id"] or path in {
                "/api/my-clinic/clinicians", "/api/patients"}):
            raise HTTPException(status_code=403, detail="Clinician access is restricted")
    return user


def admin_user(user=Depends(current_user)) -> dict:
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
    return user


def marketing_user(user=Depends(current_user)) -> dict:
    if user["role"] != "marketing":
        raise HTTPException(status_code=403, detail="Marketing team only")
    return user


def clinic_manager(user=Depends(current_user)) -> dict:
    if user['role'] not in ('marketing', 'admin'):
        raise HTTPException(status_code=403, detail='Clinic management access required')
    return user


@app.post('/api/clinic-signup', status_code=201)
def clinic_signup(body: ClinicSignup, conn=Depends(connection)):
    if '@' not in body.email or '@' not in body.clinician_email:
        raise HTTPException(status_code=400, detail='Valid email addresses are required')
    with conn.cursor() as cur:
        cur.execute('SELECT 1 FROM users WHERE lower(username)=lower(%s)', (body.username.strip(),))
        if cur.fetchone():
            raise HTTPException(status_code=409, detail='Username already exists')
        cur.execute("INSERT INTO clinics (clinic_name,contact_number,email,area,signup_source,approval_status) VALUES (%s,%s,%s,%s,'self','pending') RETURNING id", (body.clinic_name.strip(), body.contact_number.strip(), body.email.strip(), body.area.strip()))
        clinic_id = cur.fetchone()['id']
        cur.execute("INSERT INTO users (username,password,name,role,clinic_id) VALUES (%s,%s,%s,'clinic_admin',%s) RETURNING id", (body.username.strip(), hash_password(body.password), body.clinician_name.strip(), clinic_id))
        account_id = cur.fetchone()['id']
        cur.execute('INSERT INTO clinicians (name,mobile_number,email,clinic_id,clinical_role,added_by,account_id) VALUES (%s,%s,%s,%s,%s,%s,%s)', (body.clinician_name.strip(), body.clinician_mobile.strip(), body.clinician_email.strip(), clinic_id, body.clinical_role.strip(), account_id, account_id))
    return {'clinic_id': clinic_id, 'status': 'pending'}


@app.get('/api/admin/clinic-approvals')
def clinic_approvals(admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT c.*, u.name AS admin_name, u.username AS admin_username FROM clinics c JOIN users u ON u.clinic_id=c.id AND u.role='clinic_admin' WHERE c.signup_source='self' ORDER BY c.created_at DESC")
        return {'clinics': cur.fetchall()}


@app.get('/api/admin/clinics/{clinic_id}')
def admin_clinic_details(clinic_id: int, admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT id, clinic_name, contact_number, email, area, signup_source, approval_status FROM clinics WHERE id=%s", (clinic_id,))
        clinic = cur.fetchone()
        if not clinic:
            raise HTTPException(status_code=404, detail='Clinic not found')
        cur.execute("SELECT c.name, c.mobile_number, c.email, c.clinical_role, u.username FROM clinicians c LEFT JOIN users u ON u.id=c.account_id WHERE c.clinic_id=%s ORDER BY c.clinician_id", (clinic_id,))
        clinic['clinicians'] = cur.fetchall()
    return clinic


class ApprovalDecision(BaseModel):
    approved: bool
    reason: str | None = None


@app.post('/api/admin/clinic-approvals/{clinic_id}')
def decide_clinic(clinic_id: int, body: ApprovalDecision, admin=Depends(admin_user), conn=Depends(connection)):
    if not body.approved and not (body.reason or '').strip():
        raise HTTPException(status_code=400, detail='Rejection reason is required')
    with conn.cursor() as cur:
        cur.execute("UPDATE clinics SET approval_status=%s, reviewed_by=%s, reviewed_at=NOW(), rejection_reason=%s WHERE id=%s AND signup_source='self' AND approval_status='pending' RETURNING id", ('approved' if body.approved else 'rejected', admin['id'], None if body.approved else body.reason, clinic_id))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail='Pending clinic not found')
    return {'status': 'approved' if body.approved else 'rejected'}


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/api/login")
def login(body: LoginInput, conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM users WHERE lower(username) = lower(%s)",
            (body.username.strip(),),
        )
        user = cur.fetchone()
        if user is None or not verify_password(body.password, user['password']):
            raise HTTPException(status_code=401, detail="Invalid username or password")
        if user['role'] in CLINIC_ROLES:
            cur.execute('SELECT approval_status FROM clinics WHERE id=%s', (user['clinic_id'],))
            clinic = cur.fetchone()
            if clinic is None or clinic['approval_status'] != 'approved':
                raise HTTPException(status_code=403, detail='Clinic approval pending' if clinic and clinic['approval_status'] == 'pending' else 'Clinic registration rejected')
        if not user['password'].startswith('pbkdf2$'):
            cur.execute('UPDATE users SET password=%s WHERE id=%s', (hash_password(body.password), user['id']))
        token = secrets.token_urlsafe(32)
        cur.execute(
            "INSERT INTO sessions (token, user_id, expires_at) VALUES (%s, %s, %s)",
            (token, user["id"], datetime.now(timezone.utc) + timedelta(days=7)),
        )
    return {"token": token, "user": public_user(user)}


@app.get("/api/me")
def me(user=Depends(current_user)):
    return {"user": public_user(user)}


@app.post("/api/logout", status_code=204)
def logout(authorization: str = Header(), user=Depends(current_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("DELETE FROM sessions WHERE token = %s", (authorization.removeprefix("Bearer "),))


@app.get("/api/users")
def list_users(admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT id, username, name, role, created_at FROM users "
                    "WHERE role NOT IN ('clinic_admin', 'clinician') ORDER BY created_at DESC, id DESC")
        return {"users": cur.fetchall()}


@app.get("/api/planners")
def list_planners(user=Depends(current_user), conn=Depends(connection)):
    if user["role"] not in {"planning", "admin"}:
        raise HTTPException(status_code=403, detail="Planning team or admin only")
    with conn.cursor() as cur:
        cur.execute("SELECT id, name, role FROM users WHERE role = 'planning' ORDER BY name, id")
        return {"users": cur.fetchall()}


@app.get("/api/teams")
def list_teams(admin=Depends(admin_user)):
    return {"teams": TEAMS}


@app.post("/api/users", status_code=status.HTTP_201_CREATED)
def create_user(body: UserInput, admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM users WHERE lower(username) = lower(%s)", (body.username,))
        if cur.fetchone():
            raise HTTPException(status_code=409, detail="That username is already taken")
        cur.execute(
            "INSERT INTO users (username, password, name, role) VALUES (%s, %s, %s, %s) "
            "RETURNING id, username, name, role, created_at",
            (body.username, hash_password(body.password), body.name, body.role),
        )
        return {"user": cur.fetchone()}


@app.patch("/api/users/{user_id}")
def update_user(user_id: int, body: UserUpdate, admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT role FROM users WHERE id = %s AND role NOT IN ('clinic_admin', 'clinician')", (user_id,))
        user = cur.fetchone()
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        if user["role"] == "admin":
            raise HTTPException(status_code=400, detail="The admin account cannot be edited")
        cur.execute("SELECT 1 FROM users WHERE lower(username) = lower(%s) AND id <> %s", (body.username, user_id))
        if cur.fetchone():
            raise HTTPException(status_code=409, detail="That username is already taken")
        if body.password:
            cur.execute(
                "UPDATE users SET name = %s, username = %s, role = %s, password = %s WHERE id = %s "
                "RETURNING id, username, name, role, created_at",
                (body.name, body.username, body.role, hash_password(body.password), user_id),
            )
        else:
            cur.execute(
                "UPDATE users SET name = %s, username = %s, role = %s WHERE id = %s "
                "RETURNING id, username, name, role, created_at",
                (body.name, body.username, body.role, user_id),
            )
        return {"user": cur.fetchone()}


@app.delete("/api/users/{user_id}", status_code=204)
def delete_user(user_id: int, admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT role FROM users WHERE id = %s AND role NOT IN ('clinic_admin', 'clinician')", (user_id,))
        user = cur.fetchone()
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        if user["role"] == "admin":
            raise HTTPException(status_code=400, detail="The admin account cannot be deleted")
        cur.execute("DELETE FROM users WHERE id = %s", (user_id,))


@app.get("/api/clinics")
def list_clinics(user=Depends(clinic_manager), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM clinics ORDER BY clinic_name, id")
        clinics = cur.fetchall()
        cur.execute("SELECT p.*, u.role AS account_role FROM clinicians p LEFT JOIN users u ON u.id=p.account_id ORDER BY clinician_id")
        clinicians = cur.fetchall()
    by_clinic = {clinic["id"]: [] for clinic in clinics}
    for clinician in clinicians:
        if clinician["clinic_id"] in by_clinic:
            by_clinic[clinician["clinic_id"]].append(clinician)
    for clinic in clinics:
        clinic["clinicians"] = by_clinic[clinic["id"]]
    return {"clinics": clinics}


class PasswordReset(BaseModel):
    password: str = Field(min_length=8)


@app.post('/api/clinics/{clinic_id}/admin-password')
def reset_clinic_password(clinic_id: int, body: PasswordReset, user=Depends(marketing_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT id FROM clinics WHERE id=%s AND created_by=%s AND signup_source='marketing'", (clinic_id, user['id']))
        if not cur.fetchone():
            raise HTTPException(status_code=403, detail='Only the creating marketer can manage this password')
        cur.execute("UPDATE users SET password=%s WHERE clinic_id=%s AND role='clinic_admin' RETURNING id", (hash_password(body.password), clinic_id))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail='Clinic admin account not found')
        cur.execute("DELETE FROM sessions WHERE user_id IN (SELECT id FROM users WHERE clinic_id=%s AND role='clinic_admin')", (clinic_id,))
    return {'ok': True}


@app.get('/api/my-clinic')
def my_clinic(user=Depends(current_user), conn=Depends(connection)):
    if user['role'] not in CLINIC_ROLES:
        raise HTTPException(status_code=403, detail='Clinic account required')
    with conn.cursor() as cur:
        cur.execute('SELECT * FROM clinics WHERE id=%s', (user['clinic_id'],))
        clinic = cur.fetchone()
        if user['role'] == 'clinician':
            cur.execute('SELECT * FROM clinicians WHERE clinic_id=%s AND clinician_id=%s',
                        (clinic['id'], user['clinician_id']))
            clinic['clinicians'] = cur.fetchall()
            return {'clinic': clinic}
        return {'clinic': clinic_with_clinicians(cur, clinic)}


@app.post('/api/my-clinic/clinicians', status_code=201)
def add_my_clinician(body: ClinicianInput, user=Depends(current_user), conn=Depends(connection)):
    if user['role'] != 'clinic_admin':
        raise HTTPException(status_code=403, detail='Clinic admin only')
    with conn.cursor() as cur:
        person_id = body.clinician_id
        if person_id is None:
            cur.execute("INSERT INTO clinicians (name,mobile_number,email,clinic_id,clinical_role,added_by) "
                        "VALUES (%s,%s,%s,%s,%s,%s) RETURNING clinician_id",
                        (body.name, body.mobile_number, body.email, user['clinic_id'], body.clinical_role, user['id']))
            person_id = cur.fetchone()['clinician_id']
        provision_clinician(cur, user['clinic_id'], person_id, body)
        cur.execute("SELECT * FROM clinicians WHERE clinician_id=%s", (person_id,))
        return {"clinician": cur.fetchone()}


def provision_clinician(cur, clinic_id, person_id, person):
    username = (person.username or "").strip()
    if not username or not person.password:
        raise HTTPException(status_code=422, detail="Enter a clinician username and password")
    cur.execute("SELECT name, account_id FROM clinicians WHERE clinic_id=%s AND clinician_id=%s FOR UPDATE",
                (clinic_id, person_id))
    profile = cur.fetchone()
    if not profile:
        raise HTTPException(status_code=404, detail="Clinician not found")
    if profile["account_id"] is not None:
        raise HTTPException(status_code=409, detail="Clinician already has a login")
    account_id = create_clinic_account(cur, username, person.password, profile["name"], "clinician", clinic_id)
    cur.execute("UPDATE clinicians SET account_id=%s WHERE clinician_id=%s", (account_id, person_id))


def create_clinic_account(cur, username, password, name, role, clinic_id):
    cur.execute("INSERT INTO users (username,password,name,role,clinic_id) VALUES (%s,%s,%s,%s,%s) "
                "ON CONFLICT DO NOTHING RETURNING id", (username.strip(), hash_password(password), name, role, clinic_id))
    account = cur.fetchone()
    if not account:
        raise HTTPException(status_code=409, detail="Username already exists")
    return account["id"]


def save_clinicians(cur, clinic_id: int, clinicians: list[ClinicianInput], added_by: int | None = None,
                    first_is_admin: bool = False):
    ids = [person.clinician_id for person in clinicians if person.clinician_id is not None]
    if len(ids) != len(set(ids)):
        raise HTTPException(status_code=400, detail="Duplicate clinician ID")
    if ids:
        cur.execute("SELECT clinician_id FROM clinicians WHERE clinic_id = %s AND clinician_id = ANY(%s)",
                    (clinic_id, ids))
        if {row["clinician_id"] for row in cur.fetchall()} != set(ids):
            raise HTTPException(status_code=400, detail="Clinician does not belong to this clinic")
    saved_ids = []
    for index, person in enumerate(clinicians):
        person_id = person.clinician_id
        if person.clinician_id is None:
            cur.execute("INSERT INTO clinicians (name, mobile_number, email, clinic_id, clinical_role, added_by) "
                        "VALUES (%s, %s, %s, %s, %s, %s) RETURNING clinician_id",
                        (person.name, person.mobile_number, person.email, clinic_id, person.clinical_role, added_by))
            person_id = cur.fetchone()["clinician_id"]
            ids.append(person_id)
        else:
            cur.execute("UPDATE clinicians SET name = %s, mobile_number = %s, email = %s, clinical_role = %s "
                        "WHERE clinician_id = %s AND clinic_id = %s",
                        (person.name, person.mobile_number, person.email, person.clinical_role, person.clinician_id, clinic_id))
        saved_ids.append(person_id)
        if not (first_is_admin and index == 0) and (person.clinician_id is None or person.username or person.password):
            provision_clinician(cur, clinic_id, person_id, person)
    cur.execute("DELETE FROM clinicians WHERE clinic_id = %s AND account_id IS NULL AND NOT (clinician_id = ANY(%s))",
                (clinic_id, ids))
    return saved_ids


def clinic_with_clinicians(cur, clinic: dict) -> dict:
    cur.execute("SELECT p.*, u.role AS account_role FROM clinicians p LEFT JOIN users u ON u.id=p.account_id "
                "WHERE p.clinic_id = %s ORDER BY p.clinician_id", (clinic["id"],))
    clinic["clinicians"] = cur.fetchall()
    return clinic


@app.post("/api/clinics", status_code=status.HTTP_201_CREATED)
def create_clinic(body: ClinicInput, user=Depends(clinic_manager), conn=Depends(connection)):
    if not body.clinicians or not body.admin_username or not body.admin_password:
        raise HTTPException(status_code=400, detail='A clinic admin clinician, username and password are required')
    if not body.clinicians[0].email:
        raise HTTPException(status_code=400, detail='Clinic admin email is required')
    if not body.admin_username.strip() or len(body.admin_username.strip()) > 30:
        raise HTTPException(status_code=400, detail='Enter a valid clinic admin username')
    if len(body.admin_password) < 8:
        raise HTTPException(status_code=400, detail='Password must have at least 8 characters')
    if body.clinicians and any(person.clinician_id is not None for person in body.clinicians):
        raise HTTPException(status_code=400, detail="New clinicians cannot have an ID")
    with conn.cursor() as cur:
        cur.execute('SELECT 1 FROM users WHERE lower(username)=lower(%s)', (body.admin_username.strip(),))
        if cur.fetchone():
            raise HTTPException(status_code=409, detail='Username already exists')
        cur.execute(
            "INSERT INTO clinics (clinic_name, contact_number, email, area, created_by) "
            "VALUES (%s, %s, %s, %s, %s) RETURNING *",
            (body.clinic_name, body.contact_number, body.email, body.area, user["id"]),
        )
        clinic = cur.fetchone()
        saved_ids = save_clinicians(cur, clinic["id"], body.clinicians, user['id'], first_is_admin=True)
        account_id = create_clinic_account(cur, body.admin_username, body.admin_password, body.clinicians[0].name,
                                          "clinic_admin", clinic["id"])
        cur.execute("UPDATE clinicians SET account_id=%s WHERE clinician_id=%s", (account_id, saved_ids[0]))
        return {"clinic": clinic_with_clinicians(cur, clinic)}


@app.put("/api/clinics/{clinic_id}")
def update_clinic(clinic_id: int, body: ClinicInput, user=Depends(marketing_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM users WHERE clinic_id=%s AND role='clinic_admin'", (clinic_id,))
        has_admin = cur.fetchone() is not None
        if not has_admin and (not body.admin_username or not body.admin_password or len(body.admin_password) < 8 or not body.clinicians or not body.clinicians[0].email):
            raise HTTPException(status_code=400, detail='Assign a clinic admin with email, username and password')
        if not has_admin:
            cur.execute('SELECT 1 FROM users WHERE lower(username)=lower(%s)', (body.admin_username.strip(),))
            if cur.fetchone():
                raise HTTPException(status_code=409, detail='Username already exists')
        cur.execute(
            "UPDATE clinics SET clinic_name = %s, contact_number = %s, "
            "email = %s, area = %s, updated_at = NOW() WHERE id = %s RETURNING *",
            (body.clinic_name, body.contact_number, body.email, body.area, clinic_id),
        )
        clinic = cur.fetchone()
        if clinic is None:
            raise HTTPException(status_code=404, detail="Clinic not found")
        if body.clinicians is not None:
            saved_ids = save_clinicians(cur, clinic_id, body.clinicians, user['id'], first_is_admin=not has_admin)
        if not has_admin:
            account_id = create_clinic_account(cur, body.admin_username, body.admin_password, body.clinicians[0].name,
                                              "clinic_admin", clinic_id)
            first_id = saved_ids[0]
            cur.execute('UPDATE clinicians SET account_id=%s WHERE clinician_id=%s AND clinic_id=%s', (account_id, first_id, clinic_id))
        return {"clinic": clinic_with_clinicians(cur, clinic)}


@app.delete("/api/clinics/{clinic_id}", status_code=204)
def delete_clinic(clinic_id: int, user=Depends(marketing_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM patients WHERE clinic_id = %s LIMIT 1", (clinic_id,))
        if cur.fetchone():
            raise HTTPException(status_code=409, detail="Clinic has patient records")
        cur.execute("DELETE FROM clinics WHERE id = %s RETURNING id", (clinic_id,))
        if cur.fetchone() is None:
            raise HTTPException(status_code=404, detail="Clinic not found")


class OrderInput(BaseModel):
    case_id: str | None = None
    request_id: str = Field(min_length=8, max_length=100)
    patient_name: str = Field(min_length=1, max_length=160)
    patient_mobile_number: str = Field(min_length=1, max_length=30)
    patient_email: str | None = None
    clinic_patient_id: str | None = Field(default=None, max_length=100)
    clinician_id: int
    age: int | None = Field(default=None, ge=0, le=120)
    clinic_id: int
    notes: str = Field(default="", max_length=10000)


class PatientUpdate(BaseModel):
    case_id: str | None = None
    patient_name: str = Field(min_length=1, max_length=160)
    patient_mobile_number: str = Field(max_length=30)
    patient_email: str | None = None
    clinic_patient_id: str | None = Field(default=None, max_length=100)
    age: int | None = Field(default=None, ge=0, le=120)
    notes: str = Field(default="", max_length=10000)


class CommentInput(BaseModel):
    text: str = Field(min_length=1, max_length=5000)


IssueRecipient = Literal["planning", "production", "marketing", "scanner", "clinician"]


class IssueAssignment(BaseModel):
    raised_to: IssueRecipient


class IssueResolution(BaseModel):
    requires_plan_revision: bool


class IssueInput(BaseModel):
    batch_number: int | None = Field(None, ge=1)
    text: str = Field(min_length=1, max_length=5000)
    raised_to: IssueRecipient | None = None


class StatusInput(BaseModel):
    status: str
    aligner_quantity: int | None = Field(None, ge=1, strict=True)
    batch_count: int | None = Field(None, ge=1, strict=True)
    batch_number: int | None = Field(None, ge=1)
    dispatch_mode: str | None = Field(None, pattern=r"^(together|batches)$")


def workflow_view(order, number):
    batches = order.get("batches", [])
    if number is None and not batches:
        return order
    if number is None or not 1 <= number <= len(batches):
        raise HTTPException(409, "Select a batch and retry")
    if number != order["current_batch"] and (not order.get("independent_batches")
            or batches[number - 1]["status"] in {"upcoming", "qc_approved"}):
        raise HTTPException(409, "Only the current batch can be updated")
    return {**order, **batches[number - 1],
            "issues": [i for i in order["issues"] if i.get("batch_number") == number]}


def batch_transition(order, number, target, fields, guard):
    if number is None:
        return
    # Compare the complete snapshot so concurrent QC and planning cannot overwrite each other.
    guard.update(status=order["status"], batches=order["batches"])
    batches = deepcopy(order["batches"])
    batches[number - 1]["status"] = target
    for flag in ("revision_approval_required", "issue_revision_requested"):
        if flag in fields:
            batches[number - 1][flag] = fields.pop(flag)
    open_batches = {issue.get("batch_number") for issue in order.get("issues", [])
                    if issue.get("resolved_at") is None}
    if target == "issue_raised":
        open_batches.add(number)
    else:
        open_batches.discard(number)
    if open_batches:
        fields.update(batches=batches, status="issue_raised", current_batch=min(open_batches))
    elif order.get("independent_batches"):
        current = next((i for i, batch in enumerate(batches, 1) if batch["status"] != "qc_approved"), len(batches))
        batch = batches[current - 1]
        if batch["status"] == "upcoming":
            batch["status"] = "planning_in_progress"
        status = batch["status"]
        if status == "planning_in_progress" and not order.get("assigned_planner"):
            status = "submitted"
        fields.update(batches=batches, current_batch=current, status=status)
    else:
        fields.update(sequential_batch_fields(order, batches))

def sequential_batch_fields(order, batches):
    current = next((i for i, b in enumerate(batches, 1) if b["status"] != "qc_approved"), len(batches))
    if batches[current - 1]["status"] == "upcoming":
        batches[current - 1]["status"] = "planning_in_progress"
    for later in batches[current:]:
        if later["status"] == "planning_in_progress":
            later["status"] = "upcoming"
    current_status = batches[current - 1]["status"]
    if current_status == "planning_in_progress" and not order.get("assigned_planner"):
        current_status = "submitted"
    return dict(batches=batches, current_batch=current, status=current_status)


ORDER_STEPS = ["submitted", "planning_in_progress", "plan_completed", "clinician_issues", "clinician_approved",
               "manufacturing_in_process", "manufactured", "qc_issues", "qc_approved"]
STATUS_ROLES = {"plan_completed": "planning", "clinician_approved": "clinic_admin",
                "manufacturing_in_process": "production", "manufactured": "production",
                "qc_approved": "planning"}
VISIBLE_PRODUCTION_STEPS = ORDER_STEPS[4:] + ["manufacture_completed"]  # Legacy completed orders.
PLANNER_ASSIGNMENT_STEPS = ORDER_STEPS[:4]
QC_VISIBLE_STEPS = ["manufactured", "qc_issues", "qc_approved", "manufacture_completed"]


def now():
    return datetime.now(timezone.utc)


SCANNER_STEPS = ["scanner_review", "scanner_missing"]
PREPARERS = {"marketing", "scanner"} | CLINIC_ROLES
DOCUMENT_REVIEW = "planner_document_review"


def planning_visibility():
    return {"status": {"$nin": SCANNER_STEPS}, "$or": [
        {"status": DOCUMENT_REVIEW}, {"checklist": {"$exists": False}}, {"scanner_approved": True}]}


def new_checklist():
    ids = set()
    result = []
    for definition in SCANNER_CHECKLIST:
        if (not definition["id"] or definition["id"] in ids or
                not definition["label"] or definition["min_files"] < 1 or
                not definition["extensions"] or
                any(ext not in {".pdf", ".jpg", ".jpeg", ".png", ".stl"} for ext in definition["extensions"])):
            raise ValueError("Invalid SCANNER_CHECKLIST definition")
        ids.add(definition["id"])
        result.append({**deepcopy(definition), "document_ids": [], "text": "",
                       "verified": False, "waiver": None})
    return result


new_checklist()  # Fail early for invalid developer configuration.


def checklist_document_ids(doc):
    previous_items = [item for event in doc.get("scanner_history", [])
                      for item in event.get("details", {}).get("checklist", [])]
    return {document_id for item in doc.get("checklist", []) + previous_items
            for document_id in item.get("document_ids", [])}


def document_category(document, linked_ids):
    if document.get("issue_id"):
        return "issue"
    if document.get("checklist_id") or document["id"] in linked_ids:
        return "scan"
    return document.get("category")


def item_ready(item, doc):
    documents = {d["id"]: d for d in doc.get("documents", [])}
    selected = set(item.get("document_ids", []))
    valid = [documents[key] for key in selected if key in documents and
             documents[key].get("category") != "plan" and
             Path(documents[key]["name"]).suffix.lower() in item["extensions"]]
    return (item["allow_text"] and bool(item.get("text", "").strip())) or len(valid) >= item["min_files"]


class ChecklistInput(BaseModel):
    document_ids: list[str] = Field(default_factory=list)
    text: str = Field(default="", max_length=10000)
    verified: bool = False
    waiver_reason: str | None = Field(default=None, max_length=2000)


class MissingItemsInput(BaseModel):
    note: str = Field(min_length=1, max_length=5000)


def activity_event(action, user, timestamp, **details):
    return {"action": action, "actor": {key: user.get(key) for key in ("id", "name", "role")},
            "at": timestamp, "details": details}


def audited_update(update, action, user, timestamp, **details):
    update.setdefault("$set", {})["updated_at"] = timestamp
    events = update.setdefault("$push", {})
    for key in ("history", "scanner_history", "comments", "issues", "documents"):
        if key in events:
            events[key]["activity_recorded"] = True
    events["activity"] = activity_event(action, user, timestamp, **details)
    return update


def save_scanner_change(doc, fields, user, action, **details):
    timestamp = now()
    events = {"scanner_history": {"action": action, "by": user["name"], "user_id": user["id"],
                                  "at": timestamp.isoformat(), "details": fields}}
    if "status" in fields:
        events["history"] = {"status": fields["status"], "at": timestamp, "by": user["name"]}
        details.update(from_status=doc["status"], to_status=fields["status"])
    updated = order_store().find_one_and_update(
        {"order_id": doc["order_id"], "status": doc["status"], "updated_at": doc["updated_at"],
         "review_revision": doc.get("review_revision")},
        audited_update({"$set": {**fields}, "$push": events, "$inc": {"review_revision": 1}},
                       action, user, timestamp, **details),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order changed; reload and try again")
    return {"order": public_order(updated, user)}


def can_prepare_documents(doc, user):
    return user["role"] in PREPARERS and (user["role"] not in CLINIC_ROLES or
        (user.get("clinician_id") is not None and user["clinician_id"] == doc.get("clinician_id")))


def scanner_review_order(order_id, user):
    doc = get_order(order_id, user)
    if user["role"] in CLINIC_ROLES and not can_prepare_documents(doc, user):
        raise HTTPException(status_code=403, detail="Only the case clinician can map these documents")
    if doc["status"] not in SCANNER_STEPS:
        raise HTTPException(status_code=409, detail="Order is not awaiting scanner review")
    return doc


@app.get("/api/scanner/checklist")
def checklist_config(user=Depends(current_user)):
    return {"items": deepcopy(SCANNER_CHECKLIST)}


@app.put("/api/orders/{order_id}/checklist/{item_id}")
def update_checklist(order_id: str, item_id: str, body: ChecklistInput, user=Depends(current_user)):
    if user["role"] not in PREPARERS | {"admin"}:
        raise HTTPException(status_code=403, detail="Team cannot edit checklist")
    doc = scanner_review_order(order_id, user)
    checklist = deepcopy(doc["checklist"])
    item = next((i for i in checklist if i["id"] == item_id), None)
    if item is None:
        raise HTTPException(status_code=404, detail="Checklist item not found")
    if body.waiver_reason is not None:
        if user["role"] != "admin":
            raise HTTPException(status_code=403, detail="Admin only exceptions")
        if not body.waiver_reason.strip():
            raise HTTPException(status_code=422, detail="Exception reason is required")
        item["waiver"] = {"reason": body.waiver_reason.strip(), "by": user["name"],
                          "user_id": user["id"], "at": now().isoformat()}
    else:
        if body.verified and user["role"] != "scanner":
            raise HTTPException(status_code=403, detail="Only Scanner can verify items")
        docs = {d["id"]: d for d in doc["documents"]}
        if any(key not in docs or docs[key].get("category") == "plan" or
               (docs[key].get("issue_id") and key not in item["document_ids"]) or
               Path(docs[key]["name"]).suffix.lower() not in item["extensions"]
               for key in body.document_ids):
            raise HTTPException(status_code=422, detail="Select valid files from this order")
        text = item["text"] if user["role"] == "admin" else body.text.strip()
        if text and not item["allow_text"]:
            raise HTTPException(status_code=422, detail="This item requires files")
        item.update(document_ids=list(dict.fromkeys(body.document_ids)), text=text,
                    verified=body.verified, waiver=None)
        if body.verified and not item_ready(item, doc):
            raise HTTPException(status_code=409, detail="Upload all required files before verifying")
        item["verified_by"] = user["name"] if body.verified else None
        item["verified_at"] = now().isoformat() if body.verified else None
    return save_scanner_change(doc, {"checklist": checklist}, user, "Updated " + item_id,
                               item=item["label"])


@app.post("/api/orders/{order_id}/scanner/request-missing")
def request_missing(order_id: str, body: MissingItemsInput, user=Depends(current_user)):
    if user["role"] != "scanner":
        raise HTTPException(status_code=403, detail="Scanner team only")
    doc = scanner_review_order(order_id, user)
    if not body.note.strip():
        raise HTTPException(status_code=422, detail="Enter a note for Marketing")
    if (doc.get("missing_request") or {}).get("mappings"):
        raise HTTPException(status_code=409, detail="Planner corrections are pending")
    missing = [i["label"] for i in doc["checklist"] if i["mandatory"] and
               not i.get("waiver") and not (i["verified"] and item_ready(i, doc))]
    if not missing:
        raise HTTPException(status_code=409, detail="No mandatory items are missing review")
    return save_scanner_change(doc, {"status": "scanner_missing", "missing_request": {
        "note": body.note.strip(), "items": missing, "by": user["name"], "at": now().isoformat()}},
        user, "Requested missing items", items=missing)


def mapping_snapshot(item):
    return {"files": sorted(item["document_ids"]), "text": item["text"], "waiver": item.get("waiver")}


@app.post("/api/orders/{order_id}/document-review/submit")
def submit_documents(order_id: str, user=Depends(current_user)):
    if user["role"] not in PREPARERS | {"admin"}:
        raise HTTPException(status_code=403, detail="Document preparer required")
    doc = scanner_review_order(order_id, user)
    previous = (doc.get("missing_request") or {}).get("mappings", {})
    for item in doc["checklist"]:
        if item["mandatory"] and not item.get("waiver") and not item_ready(item, doc):
            raise HTTPException(status_code=409, detail="Complete " + item["label"])
        if previous.get(item["id"]) == mapping_snapshot(item):
            raise HTTPException(status_code=409, detail="Correct " + item["label"])
    return save_scanner_change(doc, {"status": DOCUMENT_REVIEW, "missing_request": None},
                               user, "Submitted documents for planner review")


class DocumentDecision(BaseModel):
    revision: int


class DocumentIssues(DocumentDecision):
    item_ids: list[str]
    note: str = Field(min_length=1, max_length=5000)


def planner_review_order(order_id, user, revision):
    if user["role"] not in {"planning", "admin"}:
        raise HTTPException(status_code=403, detail="Planner or admin required")
    doc = get_order(order_id, user)
    if doc["status"] != DOCUMENT_REVIEW or doc.get("review_revision") != revision:
        raise HTTPException(status_code=409, detail="Review changed. Reload the case.")
    return doc


@app.post("/api/orders/{order_id}/document-review/issues")
def raise_document_issues(order_id: str, body: DocumentIssues, user=Depends(current_user)):
    doc = planner_review_order(order_id, user, body.revision)
    selected = [i for i in doc["checklist"] if i["id"] in body.item_ids]
    if not selected or len(selected) != len(set(body.item_ids)) or not body.note.strip():
        raise HTTPException(status_code=422, detail="Select items and describe the correction")
    request = {"items": [i["label"] for i in selected], "note": body.note.strip(),
               "mappings": {i["id"]: mapping_snapshot(i) for i in selected},
               "by": user["name"], "at": now().isoformat()}
    return save_scanner_change(doc, {"status": "scanner_missing", "missing_request": request},
                               user, "Requested document corrections", items=request["items"])


@app.post("/api/orders/{order_id}/document-review/approve")
def approve_documents(order_id: str, body: DocumentDecision, user=Depends(current_user)):
    doc = planner_review_order(order_id, user, body.revision)
    return save_scanner_change(doc, {"status": "submitted", "scanner_approved": True,
        "planner_document_approval": {"by": user["name"], "user_id": user["id"], "at": now().isoformat()}},
        user, "Approved for Planning")


def public_order(doc, user=None):
    result = {k: v for k, v in doc.items() if k not in {"_id", "request_id", "activity", "issue_reads"}}
    viewer = (user or {}).get("id")
    receipts = doc.get("issue_reads", {}).get(str(viewer), {})
    result["issues"] = []
    for number, issue in enumerate(doc.get("issues", []), 1):
        replies = issue.get("replies", [])
        unread = sum(r.get("author_id") is not None and r["author_id"] != viewer
                     for r in replies[receipts.get(issue["id"], 0):]) if viewer is not None else 0
        result["issues"].append({**issue, "number": number, "unread": unread,
                                 "can_resolve": bool(user and can_resolve_issue(doc, issue, user))})
    result["id"] = str(doc["_id"])
    result["can_approve_revision"] = bool(user and case_clinician(doc, user))
    result["planner_assignment_open"] = doc.get("status") in PLANNER_ASSIGNMENT_STEPS
    linked_ids = checklist_document_ids(doc)
    result["documents"] = [
        {**{k: v for k, v in item.items() if k != "storage_key"},
         "category": document_category(item, linked_ids)}
        for item in doc.get("documents", [])
    ]
    for key in ("created_at", "updated_at"):
        if result.get(key):
            result[key] = result[key].isoformat() + "Z" if result[key].tzinfo is None else result[key].isoformat()
    for key in ("history", "comments", "issues", "documents"):
        for item in result.get(key, []):
            for time_key in ("at", "resolved_at"):
                if isinstance(item.get(time_key), datetime):
                    item[time_key] = item[time_key].isoformat() + "Z" if item[time_key].tzinfo is None else item[time_key].isoformat()
    return result


def clinic_order_scope(user):
    scope = {"clinic_id": user["clinic_id"]}
    if user["role"] == "clinician":
        if user.get("clinician_id") is None:
            raise HTTPException(status_code=403, detail="Clinician profile required")
        scope["clinician_id"] = user["clinician_id"]
    return scope


def case_clinician(doc, user):
    return (user["role"] in CLINIC_ROLES and user.get("clinician_id") is not None
            and user["clinician_id"] == doc.get("clinician_id"))


def can_resolve_issue(doc, issue, user):
    team = {"cad": "planning", "lab": "production"}.get(issue.get("raised_to"), issue.get("raised_to"))
    if user["role"] == "admin":
        return bool(team)
    if team == "clinician":
        return case_clinician(doc, user)
    if not issue.get("resume_status"):  # Preserve resolution rights on existing feedback.
        planner = doc.get("assigned_planner")
        if team == "planning" and planner and planner["id"] != user.get("id"):
            return False
    return team == user["role"]


def get_order(order_id: str, user: dict):
    doc = order_store().find_one({"order_id": order_id})
    if doc is None:
        raise HTTPException(status_code=404, detail="Order not found")
    if user["role"] in CLINIC_ROLES and any(doc.get(k) != v for k, v in clinic_order_scope(user).items()):
        raise HTTPException(status_code=404, detail="Order not found")
    if user["role"] in {"planning", "production"} and any(
        issue.get("resolved_at") is None and (issue.get("raised_to") == user["role"]
        or issue.get("raised_by_role") == user["role"] or
        (user["role"] == "production" and issue.get("resume_status") in VISIBLE_PRODUCTION_STEPS)) for issue in doc.get("issues", [])
    ):
        return doc
    if user["role"] == "production" and doc["status"] not in VISIBLE_PRODUCTION_STEPS and not doc.get("batches"):
        raise HTTPException(status_code=404, detail="Order not found")
    if user["role"] == "planning" and doc["status"] != DOCUMENT_REVIEW and (doc["status"] in SCANNER_STEPS or
            ("checklist" in doc and not doc.get("scanner_approved"))):
        raise HTTPException(status_code=404, detail="Order not found")
    return doc


@app.get("/api/patients")
def list_patients(clinic_id: int | None = None, q: str = "", user=Depends(current_user),
                  conn=Depends(connection)):
    if user["role"] not in {"marketing", "admin", "clinic_admin"}:
        raise HTTPException(status_code=403, detail="Patient list is restricted")
    if user["role"] == "clinic_admin":
        clinic_id = user["clinic_id"]
    term = q.strip()
    id_term = term[4:].lstrip("0") or "0" if term.upper().startswith("PAT-") else term
    with conn.cursor() as cur:
        cur.execute("SELECT patient_id, clinic_patient_id, name, mobile_number, email, "
                    "clinic_id, clinician_id FROM patients WHERE (%s::bigint IS NULL OR clinic_id = %s) "
                    "AND (%s = '' OR patient_id::text ILIKE %s OR clinic_patient_id ILIKE %s "
                    "OR name ILIKE %s OR mobile_number ILIKE %s) "
                    "ORDER BY patient_id DESC LIMIT 100",
                    (clinic_id, clinic_id, term, f"%{id_term}%", *(f"%{term}%",) * 3))
        return {"patients": [{**row, "patient_id": f"PAT-{row['patient_id']:06d}"}
                             for row in cur.fetchall()]}


@app.post("/api/orders", status_code=201)
def create_order(body: OrderInput, user=Depends(current_user), conn=Depends(connection)):
    if user["role"] not in {"admin", "marketing", "clinic_admin", "clinician"}:
        raise HTTPException(status_code=403, detail="Order submission is restricted")
    if user["role"] == "clinician" and body.clinician_id != user.get("clinician_id"):
        raise HTTPException(status_code=403, detail="Choose your own clinician profile")
    if user["role"] in CLINIC_ROLES and body.clinic_id != user["clinic_id"]:
        raise HTTPException(status_code=403, detail="Choose your own clinic")
    existing = order_store().find_one({"request_id": body.request_id})
    if existing:
        if existing["created_by"]["id"] != user["id"]:
            raise HTTPException(status_code=409, detail="Request ID already used")
        return {"order": public_order(existing, user)}
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM clinics WHERE id = %s", (body.clinic_id,))
        clinic = cur.fetchone()
        if clinic is not None:
            cur.execute("SELECT clinician_id, name, mobile_number, email FROM clinicians WHERE clinic_id = %s "
                        "ORDER BY clinician_id", (body.clinic_id,))
            clinic_people = cur.fetchall()
    if clinic is None:
        raise HTTPException(status_code=400, detail="Choose an existing clinic")
    if body.clinician_id not in {person["clinician_id"] for person in clinic_people}:
        raise HTTPException(status_code=400, detail="Choose a clinician at this clinic")
    if not body.patient_name.strip() or not body.patient_mobile_number.strip():
        raise HTTPException(status_code=422, detail="Patient name and mobile are required")
    reference = (body.clinic_patient_id or "").strip() or None
    email = (body.patient_email or "").strip() or None
    with conn.cursor() as cur:
        patient = None
        if reference:
            cur.execute("SELECT * FROM patients WHERE clinic_id = %s AND clinic_patient_id = %s",
                        (body.clinic_id, reference))
            patient = cur.fetchone()
        if patient is None:
            cur.execute("INSERT INTO patients (clinic_patient_id, name, mobile_number, email, "
                        "clinic_id, clinician_id) VALUES (%s, %s, %s, %s, %s, %s) "
                        "ON CONFLICT (clinic_id, clinic_patient_id) DO NOTHING RETURNING *",
                        (reference, body.patient_name.strip(), body.patient_mobile_number.strip(),
                         email, body.clinic_id, body.clinician_id))
            patient = cur.fetchone()
            if patient is None:
                cur.execute("SELECT * FROM patients WHERE clinic_id = %s AND clinic_patient_id = %s",
                            (body.clinic_id, reference))
                patient = cur.fetchone()
        if patient is None or (patient["name"].casefold() != body.patient_name.strip().casefold() or
                               patient["mobile_number"] != body.patient_mobile_number.strip()):
            raise HTTPException(status_code=409, detail="Clinic patient ID belongs to a different patient")
    sequence = mongo.counters.find_one_and_update(
        {"_id": "orders"}, {"$inc": {"value": 1}}, upsert=True,
        return_document=ReturnDocument.AFTER)["value"]
    timestamp = now()
    doc = {"order_id": f"ORD-{sequence:06d}", "request_id": body.request_id,
           "case_id": (body.case_id or "").strip() or None,
           "patient_id": f"PAT-{patient['patient_id']:06d}", "clinic_patient_id": patient["clinic_patient_id"],
           "patient_name": body.patient_name.strip(), "age": body.age, "notes": body.notes.strip(),
           "patient_mobile_number": patient["mobile_number"], "patient_email": patient.get("email"),
           "clinician_id": body.clinician_id,
           "clinic_id": body.clinic_id,
           "clinic": {"name": clinic["clinic_name"], "clinicians": clinic_people,
                      "contact": clinic["contact_number"], "email": clinic["email"], "area": clinic["area"]},
           "status": "scanner_review", "checklist": new_checklist(), "created_at": timestamp, "updated_at": timestamp,
           "created_by": {"id": user["id"], "name": user["name"], "role": user["role"]},
           "history": [{"status": "scanner_review", "at": timestamp, "by": user["name"],
                        "activity_recorded": True}],
           "activity": [activity_event("Order created", user, timestamp)],
           "comments": [], "issues": [], "documents": []}
    try:
        doc["_id"] = order_store().insert_one(doc).inserted_id
    except DuplicateKeyError:
        existing = order_store().find_one({"request_id": body.request_id})
        if existing and existing["created_by"]["id"] == user["id"]:
            return {"order": public_order(existing, user)}
        raise HTTPException(status_code=409, detail="Duplicate order request")
    with conn.cursor() as cur:
        cur.execute("INSERT INTO patient_orders (order_id, patient_id) VALUES (%s, %s)",
                    (doc["order_id"], patient["patient_id"]))
    return {"order": public_order(doc, user)}


def performance_period(period):
    try:
        start = datetime.strptime(period, "%Y-%m").replace(tzinfo=timezone.utc)
        end = datetime(start.year + (start.month == 12), start.month % 12 + 1, 1, tzinfo=timezone.utc)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid month")
    return start, end


@app.get("/api/performance/clinics")
def performance_clinics(marketer_id: int, period: str, admin=Depends(admin_user), conn=Depends(connection)):
    start, end = performance_period(period)
    with conn.cursor() as cur:
        cur.execute("SELECT id, clinic_name FROM clinics WHERE created_by = %s "
                    "AND created_at >= %s AND created_at < %s ORDER BY clinic_name, id",
                    (marketer_id, start, end))
        return {"clinics": cur.fetchall()}


@app.get("/api/performance")
def marketing_performance(year: int, month: int, user=Depends(admin_user), conn=Depends(connection)):
    if not 2000 <= year <= 2100 or not 1 <= month <= 12:
        raise HTTPException(status_code=400, detail="Invalid year or month")
    start, end = performance_period(f"{year}-{month:02d}")
    with conn.cursor() as cur:
        cur.execute("SELECT id, name FROM users WHERE role = 'marketing' ORDER BY name")
        marketers = cur.fetchall()
        cur.execute("SELECT created_by, COUNT(*) AS total FROM clinics "
                    "WHERE created_at >= %s AND created_at < %s GROUP BY created_by", (start, end))
        clinics_by_user = {row["created_by"]: row["total"] for row in cur.fetchall()}
    orders_by_user = {}
    cancelled = 0
    for order in order_store().find({"created_at": {"$gte": start, "$lt": end}},
                                    {"created_by": 1, "status": 1}):
        if order.get("status") == "cancelled":
            cancelled += 1
            continue
        owner = (order.get("created_by") or {}).get("id")
        orders_by_user[owner] = orders_by_user.get(owner, 0) + 1
    ranking = [{"id": row["id"], "name": row["name"],
                "orders": orders_by_user.get(row["id"], 0),
                "clinics": clinics_by_user.get(row["id"], 0)} for row in marketers]
    ranking.sort(key=lambda row: (-row["orders"], -row["clinics"], row["name"]))
    year_start = datetime(year, 1, 1, tzinfo=timezone.utc)
    year_end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    months = [{"month": i, "orders": 0, "clinics": 0} for i in range(1, 13)]
    for order in order_store().find({"created_at": {"$gte": year_start, "$lt": year_end},
                                     "status": {"$ne": "cancelled"}}, {"created_at": 1}):
        months[order["created_at"].month - 1]["orders"] += 1
    with conn.cursor() as cur:
        cur.execute("SELECT EXTRACT(MONTH FROM created_at)::int AS month, COUNT(*) AS total "
                    "FROM clinics WHERE created_at >= %s AND created_at < %s "
                    "GROUP BY 1", (year_start, year_end))
        for row in cur.fetchall():
            months[row["month"] - 1]["clinics"] = row["total"]
    return {"year": year, "month": month, "ranking": ranking, "cancelled": cancelled,
            "orders": sum(orders_by_user.values()), "clinics": sum(clinics_by_user.values()),
            "months": months}


CLINIC_GROUPS = {
    "active": SCANNER_STEPS + [DOCUMENT_REVIEW, "issue_raised"] + ORDER_STEPS[:-1],
    "scanner": SCANNER_STEPS,
    "planning": [DOCUMENT_REVIEW, "submitted", "planning_in_progress"],
    "approval": ["plan_completed"],
    "revision": ["clinician_issues"],
    "manufacturing": ["clinician_approved", "manufacturing_in_process"],
    "qc": ["manufactured", "qc_issues"],
    "completed": ["qc_approved", "manufacture_completed"],
}


@app.get("/api/my-clinic/overview")
def clinic_overview(user=Depends(current_user)):
    if user["role"] not in CLINIC_ROLES:
        raise HTTPException(status_code=403, detail="Clinic account required")
    rows = list(order_store().find(clinic_order_scope(user),
        {"documents": 0, "comments": 0, "checklist": 0}))
    counts = {key: sum(r["status"] in statuses for r in rows)
              for key, statuses in CLINIC_GROUPS.items()}
    counts["total"] = len(rows)
    counts["missing"] = sum(r["status"] == "scanner_missing" for r in rows)
    counts["cancelled"] = sum(r["status"] == "cancelled" for r in rows)
    year = now().year
    months = [0] * 12
    clinicians = {}
    summaries = []
    for row in rows:
        created = row["created_at"]
        if created.year == year:
            months[created.month - 1] += 1
        person = clinicians.setdefault(str(row.get("clinician_id", "")),
            {"total": 0, "active": 0, "approval": 0})
        person["total"] += 1
        person["active"] += row["status"] in CLINIC_GROUPS["active"]
        person["approval"] += row["status"] == "plan_completed"
        entered = next((h["at"] for h in reversed(row.get("history", []))
                        if h["status"] == row["status"]), created)
        summaries.append({"order_id": row["order_id"], "patient_name": row["patient_name"],
            "clinician_id": row.get("clinician_id"), "status": row["status"],
            "updated_at": row.get("updated_at", created).isoformat(),
            "stage_since": entered.isoformat() if isinstance(entered, datetime) else entered,
            "revised": any(h["status"] == "clinician_issues" for h in row.get("history", [])) or
                       any(i.get("requires_plan_revision") for i in row.get("issues", [])),
            "missing_request": row.get("missing_request") if row["status"] == "scanner_missing" else None})
    return {"counts": counts, "year": year, "months": months, "clinicians": clinicians,
            "approvals": sorted([r for r in summaries if r["status"] == "plan_completed"], key=lambda r: r["stage_since"]),
            "missing": sorted([r for r in summaries if r["status"] == "scanner_missing"], key=lambda r: r["stage_since"]),
            "recent": sorted(summaries, key=lambda r: r["updated_at"], reverse=True)[:10]}


ADMIN_STAGE_GROUPS = {
    "scanner": SCANNER_STEPS,
    "document_review": [DOCUMENT_REVIEW],
    "in_plan": ["submitted", "planning_in_progress", "plan_completed", "clinician_issues"],
    "in_manufacturing": ["clinician_approved", "manufacturing_in_process"],
    "in_qc": ["manufactured", "qc_issues"],
    "completed": ["qc_approved", "manufacture_completed"],
    "cancelled": ["cancelled"],
    "review_pending": ["plan_completed"],
}


@app.get("/api/orders")
def list_orders(q: str = "", status_filter: str = "", status_group: str = "", view: str = "",
                clinic_id: int | None = None, page: int = 1, limit: int = 25, mine: bool = False, scanner_approved: bool = False,
    scanner_missing: bool = False, issue_queue: bool = False, clinician_id: int | None = None, created_month: str = "",
                admin_bucket: str = "",
                marketer_id: int | None = None, period: str = "", batches_only: bool = False,
                user=Depends(current_user)):
    if page < 1 or not 1 <= limit <= 100:
        raise HTTPException(status_code=400, detail="Invalid page or limit")
    query = {}
    if user['role'] in CLINIC_ROLES:
        query.update(clinic_order_scope(user))
    if clinician_id is not None or created_month:
        if user["role"] not in CLINIC_ROLES or (user["role"] == "clinician" and clinician_id not in (None, user["clinician_id"])):
            raise HTTPException(status_code=403, detail="Clinician filter is restricted")
        if clinician_id is not None:
            query["clinician_id"] = clinician_id
        if created_month:
            try:
                start = datetime.strptime(created_month, "%Y-%m").replace(tzinfo=timezone.utc)
                end = datetime(start.year + (start.month == 12), start.month % 12 + 1, 1, tzinfo=timezone.utc)
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid month")
            query["created_at"] = {"$gte": start, "$lt": end}
    if scanner_approved:
        query["scanner_approved"] = True
    if scanner_missing:
        query["status"] = {"$in": SCANNER_STEPS}
        query["checklist"] = {"$elemMatch": {"mandatory": True, "verified": False, "waiver": None}}
    if mine and user["role"] not in {"planning", "admin"}:
        raise HTTPException(status_code=403, detail="Planning team only")
    if mine:
        query["assigned_planner.id"] = user["id"]
    qc_view = view == "qc"
    production_view = (user["role"] == "production" and not qc_view and not issue_queue) or (view == "production" and user["role"] == "admin")
    if view and not (view == "production" and production_view):
        if not qc_view or user["role"] not in QC_REVIEW_ROLES:
            raise HTTPException(status_code=403, detail="QC view is restricted")
        query["status"] = {"$in": QC_VISIBLE_STEPS}
    if production_view:
        query["status"] = {"$in": VISIBLE_PRODUCTION_STEPS}
    if status_group:
        cad_groups = {
            "document_review": [DOCUMENT_REVIEW],
            "plan_pending": ["submitted"],
            "planning_in_progress": ["planning_in_progress"],
            "clinical_approval_pending": ["plan_completed"],
            "issue_raised": ["clinician_issues", "issue_raised"],
            "approved": ["clinician_approved", "manufacturing_in_process", "manufactured", "qc_issues",
                         "qc_approved", "manufacture_completed"],
            "cancelled": ["cancelled"],
        }
        lab_groups = {
            "manufacturing_not_started": ["clinician_approved"],
            "manufacturing_in_process": ["manufacturing_in_process"],
            "qc_approval_pending": ["manufactured"],
            "qc_issue_raised": ["qc_issues"],
            "manufacturing_completed": ["qc_approved", "manufacture_completed"],
        }
        qc_groups = {
            "qc_approval_pending": ["manufactured"],
            "qc_issue_raised": ["qc_issues"],
            "qc_issue_resolved": ["manufactured"],
            "qc_approval_completed": ["qc_approved", "manufacture_completed"],
        }
        groups = (qc_groups if qc_view else {**cad_groups, **qc_groups} if user["role"] == "planning" else
                  lab_groups if production_view else cad_groups if user["role"] == "admin" else
                  CLINIC_GROUPS if user["role"] in CLINIC_ROLES else {})
        if status_group not in groups:
            raise HTTPException(status_code=400, detail="Invalid status group")
        query["status"] = {"$in": groups[status_group]}
        if (qc_view or user["role"] == "planning") and status_group == "qc_issue_resolved":
            query["$expr"] = resolved_qc_expression()
        elif (qc_view or user["role"] == "planning") and status_group == "qc_approval_pending":
            query["$expr"] = {"$not": [resolved_qc_expression()]}
    if clinic_id is not None:
        if user["role"] not in {"planning", "admin"} and not production_view and not qc_view:
            raise HTTPException(status_code=403, detail="Team cannot filter clinics")
        query["clinic_id"] = clinic_id
    if status_filter:
        if status_group:
            raise HTTPException(status_code=400, detail="Choose one status filter")
        if production_view or qc_view:
            matching = ["qc_approved", "manufacture_completed"] if status_filter == "qc_approved" else [status_filter]
            visible = QC_VISIBLE_STEPS if qc_view else VISIBLE_PRODUCTION_STEPS
            query["status"] = {"$in": matching if status_filter in visible else []}
        else:
            query["status"] = {"$in": ["qc_approved", "manufacture_completed"]} if status_filter == "qc_approved" else status_filter
    if q.strip():
        import re
        pattern = re.escape(q.strip()[:100])
        query["$or"] = [{field: {"$regex": pattern, "$options": "i"}}
                        for field in ("order_id", "patient_name", "clinic.name", "clinic.dentist")]
    if issue_queue:
        role = user["role"]
        recipients = {"marketing": ["marketing", None], "admin": [None],
                      "planning": ["planning", "cad"], "production": ["production", "lab"]}
        if role in CLINIC_ROLES:
            query["clinician_id"] = user.get("clinician_id") or -1
            teams = ["clinician"]
        else:
            teams = recipients.get(role, [role])
        query["issues"] = {"$elemMatch": {"resolved_at": None} if role == "admin" else {"raised_to": {"$in": teams}, "resolved_at": None}}
    if user["role"] == "planning" and not issue_queue:
        query["$and"] = [planning_visibility()]
    if user["role"] == "scanner" and not issue_queue:
        query.setdefault("checklist", {"$exists": True})
    if admin_bucket or marketer_id is not None:
        if user["role"] != "admin" or view:
            raise HTTPException(status_code=403, detail="Admin filters are restricted")
    if admin_bucket in ADMIN_STAGE_GROUPS:
        query.setdefault("$and", []).append({"status": {"$in": ADMIN_STAGE_GROUPS[admin_bucket]}})
    elif admin_bucket == "open_issues":
        query["issues"] = {"$elemMatch": {"resolved_at": None}}
    elif admin_bucket:
        raise HTTPException(status_code=400, detail="Invalid dashboard filter")
    if marketer_id is not None:
        start, end = performance_period(period)
        query["created_at"] = {"$gte": start, "$lt": end}
        query["created_by.id"] = marketer_id
        query.setdefault("$and", []).append({"status": {"$ne": "cancelled"}})
    if (qc_view or production_view) and "status" in query:
        visible = QC_VISIBLE_STEPS if qc_view else VISIBLE_PRODUCTION_STEPS
        if (not status_group and not status_filter) or status_group == "qc_issue_raised" or status_filter == "issue_raised":
            query["status"]["$in"] = list(query["status"]["$in"]) + ["issue_raised"]
            query.setdefault("$and", []).append(issue_stage_scope(
                ["manufactured"] if status_group == "qc_issue_raised" else visible))
    if batches_only:
        query["dispatch_mode"] = "batches"
        if production_view and not status_filter and not status_group:
            query.pop("status", None)
    collection = order_store()
    total = collection.count_documents(query)
    offset = (page - 1) * limit
    rows = collection.find(query).sort("created_at", DESCENDING).skip(offset).limit(limit)
    return {"orders": [public_order(row, user) for row in rows], "total": total, "page": page}


@app.get("/api/cad/overview")
def cad_overview(user=Depends(current_user)):
    if user["role"] != "planning":
        raise HTTPException(status_code=403, detail="Planning team only")
    collection = order_store()
    statuses = {row["_id"]: row["count"] for row in collection.aggregate([
        {"$match": planning_visibility()},
        {"$group": {"_id": "$status", "count": {"$sum": 1}}},
    ])}
    clinics = [{"id": row["_id"], "name": row["name"]}
               for row in collection.aggregate([
                   {"$match": {"clinic_id": {"$ne": None}, **planning_visibility()}},
                   {"$group": {"_id": "$clinic_id", "name": {"$first": "$clinic.name"}}},
                   {"$sort": {"name": 1}},
               ])]
    return {"all_orders": sum(statuses.values()),
            "document_review": statuses.get(DOCUMENT_REVIEW, 0),
            "plan_pending": statuses.get("submitted", 0),
            "planning_in_progress": statuses.get("planning_in_progress", 0),
            "clinical_approval_pending": statuses.get("plan_completed", 0),
            "issue_raised": statuses.get("clinician_issues", 0) + statuses.get("issue_raised", 0),
            "approved": sum(statuses.get(key, 0) for key in
                            ("clinician_approved", "manufacturing_in_process", "manufactured", "qc_issues",
                             "qc_approved", "manufacture_completed")),
            "cancelled": statuses.get("cancelled", 0), "clinics": clinics}


def issue_stage_scope(stages):
    return {"$or": [{"status": {"$ne": "issue_raised"}},
                    {"issues": {"$elemMatch": {"resolved_at": None, "resume_status": {"$in": stages}}}}]}


@app.get("/api/lab/overview")
def lab_overview(user=Depends(current_user)):
    if user["role"] not in {"production", "admin"}:
        raise HTTPException(status_code=403, detail="Production team or admin only")
    collection = order_store()
    statuses = {row["_id"]: row["count"] for row in collection.aggregate([
        {"$match": {"status": {"$in": VISIBLE_PRODUCTION_STEPS + ["issue_raised"]}, **issue_stage_scope(VISIBLE_PRODUCTION_STEPS)}},
        {"$group": {"_id": "$status", "count": {"$sum": 1}}},
    ])}
    clinics = [{"id": row["_id"], "name": row["name"]}
               for row in collection.aggregate([
                   {"$match": {"status": {"$in": VISIBLE_PRODUCTION_STEPS + ["issue_raised"]}, **issue_stage_scope(VISIBLE_PRODUCTION_STEPS),
                               "clinic_id": {"$ne": None}}},
                   {"$group": {"_id": "$clinic_id", "name": {"$first": "$clinic.name"}}},
                   {"$sort": {"name": 1}},
               ])]
    return {"all_orders": sum(statuses.values()),
            "manufacturing_not_started": statuses.get("clinician_approved", 0),
            "manufacturing_in_process": statuses.get("manufacturing_in_process", 0),
            "qc_approval_pending": statuses.get("manufactured", 0),
            "qc_issue_raised": statuses.get("qc_issues", 0) + collection.count_documents({
                "status": "issue_raised", **issue_stage_scope(["manufactured"])}),
            "manufacturing_completed": statuses.get("qc_approved", 0) +
                                       statuses.get("manufacture_completed", 0),
            "clinics": clinics}


def resolved_qc_expression():
    return {"$anyElementTrue": [{"$map": {
        "input": {"$ifNull": ["$issues", []]}, "as": "issue",
        "in": {"$and": [
            {"$or": [{"$eq": ["$$issue.resume_status", "manufactured"]},
                     {"$and": [{"$eq": [{"$ifNull": ["$$issue.resume_status", None]}, None]},
                               {"$in": ["$$issue.raised_to", ["production", "lab"]]}]}]},
            {"$ne": [{"$ifNull": ["$$issue.resolved_at", None]}, None]},
            {"$eq": [{"$ifNull": ["$$issue.batch_number", 0]}, {"$ifNull": ["$current_batch", 0]}]},
        ]}}}]}


@app.get("/api/qc/overview")
def qc_overview(user=Depends(current_user)):
    if user["role"] not in QC_REVIEW_ROLES:
        raise HTTPException(status_code=403, detail="QC reviewer required")
    collection = order_store()
    statuses = {row["_id"]: row["count"] for row in collection.aggregate([
        {"$match": {"status": {"$in": QC_VISIBLE_STEPS + ["issue_raised"]}, **issue_stage_scope(QC_VISIBLE_STEPS)}},
        {"$group": {"_id": "$status", "count": {"$sum": 1}}},
    ])}
    resolved = collection.count_documents({"status": "manufactured", "$expr": resolved_qc_expression()})
    clinics = [{"id": row["_id"], "name": row["name"]}
               for row in collection.aggregate([
                   {"$match": {"status": {"$in": QC_VISIBLE_STEPS + ["issue_raised"]}, **issue_stage_scope(QC_VISIBLE_STEPS),
                               "clinic_id": {"$ne": None}}},
                   {"$group": {"_id": "$clinic_id", "name": {"$first": "$clinic.name"}}},
                   {"$sort": {"name": 1}},
               ])]
    return {"all_orders": sum(statuses.values()),
            "qc_approval_pending": statuses.get("manufactured", 0) - resolved,
            "qc_issue_raised": statuses.get("qc_issues", 0) + statuses.get("issue_raised", 0),
            "qc_issue_resolved": resolved,
            "qc_approval_completed": statuses.get("qc_approved", 0) +
                                  statuses.get("manufacture_completed", 0),
            "clinics": clinics}


@app.get("/api/admin/overview")
def admin_overview(admin=Depends(admin_user), conn=Depends(connection), detailed: bool = False):
    rows = list(order_store().aggregate([
        {"$project": {"status": 1, "open_issues": {"$size": {"$filter": {
            "input": {"$ifNull": ["$issues", []]}, "as": "issue",
            "cond": {"$eq": [{"$ifNull": ["$$issue.resolved_at", None]}, None]}}}}}},
        {"$group": {"_id": "$status", "count": {"$sum": 1},
                    "open_issues": {"$sum": "$open_issues"},
                    "open_issue_orders": {"$sum": {"$cond": [{"$gt": ["$open_issues", 0]}, 1, 0]}}}},
    ]))
    statuses = {row["_id"]: row["count"] for row in rows}
    open_issues = sum(row["open_issues"] for row in rows)
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS count FROM users WHERE role NOT IN ('clinic_admin', 'clinician')")
        users = cur.fetchone()["count"]
    result = {"total_orders": sum(statuses.values()), "users": users, "open_issues": open_issues,
              **{name: sum(statuses.get(key, 0) for key in group)
                 for name, group in ADMIN_STAGE_GROUPS.items()
                 if detailed or name not in {"scanner", "document_review", "review_pending"}}}
    if detailed:
        result["open_issue_orders"] = sum(row["open_issue_orders"] for row in rows)
    return result


@app.get("/api/orders/{order_id}")
def order_detail(order_id: str, user=Depends(current_user)):
    doc = get_order(order_id, user)
    return {"order": {**public_order(doc, user), "can_prepare_documents": can_prepare_documents(doc, user)}}


def activity_time(value):
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value)
        except ValueError:
            return None
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=value.tzinfo or timezone.utc).astimezone(timezone.utc)


def order_activity(doc):
    entries = []
    covered_status = {}
    resolutions = set()
    issue_statuses = {"production": ("qc_issues", "manufactured"),
                      "planning": ("clinician_issues", "plan_completed")}
    team_aliases = {"lab": "production", "cad": "planning"}

    def status_key(timestamp, status, actor):
        if timestamp is not None:
            timestamp = timestamp.replace(microsecond=timestamp.microsecond // 1000 * 1000)
        return timestamp, status, actor

    def add(event):
        timestamp = activity_time(event.get("at"))
        entries.append({**event, "at": timestamp})
        return entries[-1]

    for event in doc.get("activity", []):
        add(event)
        if event["action"] == "Issue resolved":
            resolutions.add(event["details"].get("issue_id"))

    def legacy(action, source, timestamp=None, actor=None, **details):
        return add(activity_event(action, actor or {
            "name": source.get("by"), "id": source.get("user_id"), "role": source.get("role"),
        }, timestamp if timestamp is not None else source.get("at"), **details))

    def cover_status(event, status):
        if status:
            covered_status[status_key(event["at"], status, event["actor"].get("name"))] = event

    if not any(event["action"] == "Order created" for event in entries):
        creation = legacy("Order created", {}, doc.get("created_at"), doc.get("created_by"))
        first = next(iter(doc.get("history", [])), {})
        if creation["at"] is not None and creation["at"] == activity_time(first.get("at")):
            cover_status(creation, first.get("status"))

    for event in doc.get("scanner_history", []):
        if not event.get("activity_recorded"):
            status = event.get("details", {}).get("status")
            entry = legacy(event.get("action") or "Document review updated", event, to_status=status)
            cover_status(entry, status)
    for event in doc.get("comments", []):
        if not event.get("activity_recorded"):
            legacy("Comment added", event, comment_id=event.get("id"))
    for event in doc.get("documents", []):
        if not event.get("activity_recorded"):
            legacy("Document uploaded", event, document=event.get("name"))
    for issue in doc.get("issues", []):
        team = issue.get("raised_to")
        raised_status, closed_status = issue_statuses.get(team_aliases.get(team, team), (None, None))
        if not issue.get("activity_recorded"):
            raised = legacy("Issue raised", issue, issue_id=issue.get("id"))
            cover_status(raised, raised_status)
        if issue.get("resolved_at") and issue.get("id") not in resolutions:
            resolved_at = activity_time(issue["resolved_at"])
            transition = next((row for row in doc.get("history", [])
                               if closed_status and resolved_at == activity_time(row.get("at"))
                               and row.get("status") == closed_status), {})
            resolved = legacy("Issue resolved", transition, issue["resolved_at"], issue_id=issue.get("id"))
            if transition:
                cover_status(resolved, closed_status)

    previous_status = None
    for row in doc.get("history", []):
        status = row.get("status")
        if not row.get("activity_recorded"):
            entry = covered_status.get(status_key(activity_time(row.get("at")), status, row.get("by")))
            if entry is None:
                if status == "planning_in_progress":
                    planner = doc.get("assigned_planner") or {}
                    entry = legacy("Planner assigned", row, assignee=planner.get("name"))
                else:
                    entry = legacy("Status changed", row)
            entry["details"].update(from_status=previous_status, to_status=status)
        previous_status = status

    entries.reverse()
    entries.sort(key=lambda entry: entry["at"] or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    return entries


@app.get("/api/orders/{order_id}/activity")
def order_activity_detail(order_id: str, user=Depends(current_user)):
    return {"activity": order_activity(get_order(order_id, user))}


@app.put("/api/orders/{order_id}/patient")
def edit_patient(order_id: str, body: PatientUpdate, user=Depends(marketing_user),
                 conn=Depends(connection)):
    order = get_order(order_id, user)
    reference = (body.clinic_patient_id or "").strip() or None
    email = (body.patient_email or "").strip() or None
    with conn.cursor() as cur:
        cur.execute("SELECT patient_id FROM patient_orders WHERE order_id = %s", (order_id,))
        linked = cur.fetchone()
        if linked:
            try:
                cur.execute("UPDATE patients SET clinic_patient_id = %s, name = %s, "
                            "mobile_number = %s, email = %s, updated_at = NOW() "
                            "WHERE patient_id = %s",
                            (reference, body.patient_name.strip(), body.patient_mobile_number.strip(),
                             email, linked["patient_id"]))
            except psycopg.errors.UniqueViolation:
                raise HTTPException(status_code=409, detail="Clinic patient ID already belongs to another patient")
    timestamp = now()
    shared = {"clinic_patient_id": reference, "patient_name": body.patient_name.strip(),
              "patient_mobile_number": body.patient_mobile_number.strip(), "patient_email": email}
    if linked:
        order_store().update_many(
            {"patient_id": f"PAT-{linked['patient_id']:06d}", "order_id": {"$ne": order_id},
             "$or": [{key: {"$ne": value}} for key, value in shared.items()]},
            audited_update({"$set": shared.copy()}, "Linked patient details updated", user, timestamp))
    fields = {**shared, "age": body.age, "notes": body.notes.strip()}
    if "case_id" in body.model_fields_set:
        fields["case_id"] = (body.case_id or "").strip() or None
    changed = [key for key, value in fields.items() if order.get(key) != value]
    if changed:
        order_store().update_one({"order_id": order_id}, audited_update(
            {"$set": fields}, "Patient details edited", user, timestamp, fields=changed))
    return {"order": public_order(get_order(order_id, user), user)}


@app.post("/api/orders/{order_id}/comments", status_code=201)
def add_comment(order_id: str, body: CommentInput, user=Depends(current_user)):
    get_order(order_id, user)
    timestamp = now()
    comment_id = str(ObjectId())
    order_store().update_one({"order_id": order_id}, audited_update({"$push": {"comments": {
        "id": comment_id, "text": body.text.strip(), "at": timestamp,
        "by": user["name"], "role": user["role"]}}}, "Comment added", user, timestamp,
        comment_id=comment_id))
    return {"order": public_order(get_order(order_id, user), user)}


@app.post("/api/orders/{order_id}/issues", status_code=201)
def add_issue(order_id: str, body: IssueInput, user=Depends(current_user)):
    order = get_order(order_id, user)
    doc = workflow_view(order, body.batch_number)
    if not body.text.strip():
        raise HTTPException(422, "Describe the issue before submitting")
    if doc["status"] not in ORDER_STEPS[:-1] + SCANNER_STEPS + [DOCUMENT_REVIEW, "issue_raised"]:
        raise HTTPException(409, "Only active cases can receive issues")
    target_team = None if user["role"] in CLINIC_ROLES else body.raised_to
    if target_team == user["role"]:
        raise HTTPException(422, "Choose a recipient outside your own team")
    if user["role"] not in CLINIC_ROLES and target_team is None:
        raise HTTPException(422, "Choose the team or clinician responsible")
    if target_team == "clinician" and not order.get("clinician_id"):
        raise HTTPException(422, "This case has no assigned clinician")
    timestamp = now()
    issue_id = str(ObjectId())
    source_status = doc["status"]
    issue_status = "issue_raised"
    open_issue = next((item for item in doc.get("issues", []) if not item.get("resolved_at") and item.get("resume_status")), {})
    resume_status = open_issue.get("resume_status") or {
        "clinician_issues": "plan_completed", "qc_issues": "manufactured"
    }.get(source_status, source_status)
    guard = {"order_id": order_id, "status": source_status, "issue_revision": order.get("issue_revision")}
    fields = {"status": issue_status}
    batch_transition(order, body.batch_number, issue_status, fields, guard)
    events = {"issues": {"id": issue_id, "text": body.text.strip(), "at": timestamp, "by": user["name"],
                         "raised_by_id": user.get("id"), "raised_by_role": user["role"], "raised_to": target_team,
                         "assigned_by": user["name"] if target_team else None,
                         "resume_status": resume_status,
                         "resolved_at": None, "batch_number": body.batch_number}}
    if source_status != issue_status:
        events["history"] = {"status": issue_status, "at": timestamp, "by": user["name"]}
    updated = order_store().find_one_and_update(
        guard, audited_update({"$push": events, "$set": fields, "$inc": {"issue_revision": 1}},
         "Issue raised", user, timestamp, batch_number=body.batch_number,
         issue_id=issue_id, raised_to=target_team, from_status=source_status, to_status=issue_status),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order changed; reload and try again")
    return {"order": public_order(updated, user), "issue_id": issue_id}


@app.post("/api/orders/{order_id}/issues/{issue_id}/replies", status_code=201)
def add_issue_reply(order_id: str, issue_id: str, body: CommentInput, user=Depends(current_user)):
    get_order(order_id, user)
    text = body.text.strip()
    if not text:
        raise HTTPException(422, "Write a reply before posting")
    timestamp = now()
    reply = {"id": str(ObjectId()), "text": text, "at": timestamp.isoformat(),
             "by": user["name"], "role": user["role"], "author_id": user["id"]}
    updated = order_store().find_one_and_update(
        {"order_id": order_id, "issues": {"$elemMatch": {"id": issue_id, "resolved_at": None}}},
        audited_update({"$push": {"issues.$.replies": reply}}, "Issue reply posted",
                       user, timestamp, issue_id=issue_id, reply_id=reply["id"]),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        if any(i["id"] == issue_id for i in get_order(order_id, user)["issues"]):
            raise HTTPException(409, "This issue is resolved. Its conversation is closed.")
        raise HTTPException(404, "Issue not found")
    return {"order": public_order(updated, user)}


class IssueRead(BaseModel):
    through_reply_id: str


@app.post("/api/orders/{order_id}/issues/{issue_id}/read")
def mark_issue_read(order_id: str, issue_id: str, body: IssueRead, user=Depends(current_user)):
    doc = get_order(order_id, user)
    issue = next((i for i in doc["issues"] if i["id"] == issue_id), None)
    if issue is None:
        raise HTTPException(404, "Issue not found")
    # Replies are append-only. An older tab cannot rewind a receipt or clear newer arrivals.
    position = next((n for n, r in enumerate(issue.get("replies", []), 1)
                     if r["id"] == body.through_reply_id), None)
    if position is None:
        raise HTTPException(422, "Reply does not belong to this issue")
    order_store().update_one({"order_id": order_id},
                             {"$max": {f"issue_reads.{user['id']}.{issue_id}": position}})
    return {"read_through": position}


@app.post("/api/orders/{order_id}/issues/{issue_id}/assign")
def assign_issue(order_id: str, issue_id: str, body: IssueAssignment, user=Depends(current_user)):
    if user["role"] not in {"marketing", "admin"}:
        raise HTTPException(403, "Marketing or Admin assigns clinician issues")
    order = get_order(order_id, user)
    if body.raised_to == "clinician" and not order.get("clinician_id"):
        raise HTTPException(422, "This case has no assigned clinician")
    timestamp = now()
    updated = order_store().find_one_and_update(
        {"order_id": order_id, "issues": {"$elemMatch": {"id": issue_id, "resolved_at": None, "raised_to": None}}},
        audited_update({"$set": {"issues.$.raised_to": body.raised_to, "issues.$.assigned_by": user["name"]},
                        "$inc": {"issue_revision": 1}}, "Issue assigned", user, timestamp,
                       issue_id=issue_id, raised_to=body.raised_to), return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(409, "Issue is no longer awaiting assignment")
    return {"order": public_order(updated, user)}


@app.post("/api/orders/{order_id}/issues/{issue_id}/resolve")
def resolve_issue(order_id: str, issue_id: str, user=Depends(current_user), body: IssueResolution | None = None):
    doc = get_order(order_id, user)
    issue = next((item for item in doc["issues"] if item["id"] == issue_id), None)
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    order = doc
    doc = workflow_view(order, issue.get("batch_number"))
    if not can_resolve_issue(order, issue, user):
        raise HTTPException(403, "Only the assigned recipient can resolve this issue")
    if issue.get("resume_status") and body is None:
        raise HTTPException(422, "Indicate whether the plan requires revision")
    issue_status = doc["status"]
    if issue_status not in {"issue_raised", "qc_issues", "clinician_issues"} or issue.get("resolved_at") is not None:
        raise HTTPException(409, "Issue is not open for resolution")
    revision = bool(body and body.requires_plan_revision)
    revise_plan = revision or doc.get("issue_revision_requested", False)
    return_status = issue.get("resume_status") or ("manufactured" if issue.get("raised_to") in {"lab", "production"}
                                                  else "plan_completed")
    if revise_plan and return_status not in SCANNER_STEPS + [DOCUMENT_REVIEW, "submitted"]:
        return_status = "planning_in_progress" if order.get("assigned_planner") or order.get("batches") else "submitted"
    timestamp = now()
    remaining = [item for item in doc["issues"] if item["id"] != issue_id and item["resolved_at"] is None]
    update = {
        "$set": {"issues.$.resolved_at": timestamp, "issues.$.resolved_by": user["name"],
                 "issues.$.requires_plan_revision": revision, "issue_revision_requested": bool(remaining and revise_plan)},
        "$inc": {"issue_revision": 1},
    }
    if not remaining:
        update["$set"]["status"] = return_status
        if revise_plan:
            update["$set"]["revision_approval_required"] = True
        update["$push"] = {"history": {"status": return_status, "at": timestamp, "by": user["name"]}}
    details = {"issue_id": issue_id, "batch_number": issue.get("batch_number"), "requires_plan_revision": revision}
    if not remaining:
        details.update(from_status=issue_status, to_status=return_status)
    guard = {"order_id": order_id, "status": issue_status, "issue_revision": order.get("issue_revision"),
             "issues": {"$elemMatch": {"id": issue_id, "resolved_at": None}}}
    batch_transition(order, issue.get("batch_number"), issue_status if remaining else return_status, update["$set"], guard)
    updated = order_store().find_one_and_update(
        guard,
        audited_update(update, "Issue resolved", user, timestamp, **details),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order changed; reload and try again")
    return {"order": public_order(updated, user)}


@app.post("/api/orders/{order_id}/assign")
def assign_order(order_id: str, user=Depends(current_user)):
    if user["role"] != "planning":
        raise HTTPException(status_code=403, detail="Planning team only")
    timestamp = now()
    updated = order_store().find_one_and_update(
        {"order_id": order_id, "status": "submitted", "assigned_planner": None, "scanner_approved": True},
        audited_update({"$set": {"status": "planning_in_progress", "assigned_planner": {"id": user["id"], "name": user["name"]}, "assigned_at": timestamp, "assigned_by": {"id": user["id"], "name": user["name"]}},
         "$push": {"history": {"status": "planning_in_progress", "at": timestamp, "by": user["name"]}}},
         "Planner assigned", user, timestamp, assignee=user["name"],
         from_status="submitted", to_status="planning_in_progress"),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order already assigned or unavailable")
    return {"order": public_order(updated, user)}


class AdminAssignment(BaseModel):
    user_id: int


class AssignmentChange(BaseModel):
    user_id: int | None = None
    reason: str | None = None


@app.post("/api/orders/{order_id}/assignment")
def change_assignment(order_id: str, body: AssignmentChange, user=Depends(current_user), conn=Depends(connection)):
    if user["role"] not in {"planning", "admin"}:
        raise HTTPException(status_code=403, detail="Planning team or admin only")
    doc = get_order(order_id, user)
    previous = doc.get("assigned_planner")
    if not previous:
        raise HTTPException(status_code=409, detail="Order is unassigned")
    if doc["status"] not in PLANNER_ASSIGNMENT_STEPS:
        raise HTTPException(status_code=409, detail="Planner assignment is closed for this order stage")
    if user["role"] == "planning":
        if doc["status"] != "planning_in_progress" or previous.get("id") != user["id"]:
            raise HTTPException(status_code=403, detail="Only the assigned planner can change this assignment")
        assigned_by = doc.get("assigned_by")
        if assigned_by and assigned_by.get("id") != user["id"]:
            raise HTTPException(status_code=403, detail="Only self-claimed orders can be changed")
        if not body.reason or not body.reason.strip():
            raise HTTPException(status_code=400, detail="A reason is required")
    elif body.user_id is None and (previous.get("id") != user["id"] or doc["status"] != "planning_in_progress"):
        raise HTTPException(status_code=403, detail="Admin can drop only an order assigned to themselves")
    assignee = None
    if body.user_id is not None:
        if body.user_id == user["id"]:
            assignee = user
        else:
            with conn.cursor() as cur:
                cur.execute("SELECT id, name, role FROM users WHERE id = %s", (body.user_id,))
                assignee = cur.fetchone()
        if not assignee or assignee["role"] != "planning" and not (assignee["role"] == "admin" and assignee["id"] == user["id"]):
            raise HTTPException(status_code=400, detail="Select a planning team member")
        if assignee["id"] == previous.get("id"):
            raise HTTPException(status_code=409, detail="Assignee is unchanged")
    timestamp = now()
    fields = {"assigned_planner": {"id": assignee["id"], "name": assignee["name"]} if assignee else None,
              "assigned_at": timestamp if assignee else None,
              "assigned_by": {"id": user["id"], "name": user["name"]} if assignee else None}
    if not assignee and doc["status"] == "planning_in_progress":
        fields["status"] = "submitted"
    updated = order_store().find_one_and_update(
        {"order_id": order_id, "status": doc["status"], "assigned_planner.id": previous["id"],
         "assigned_at": doc.get("assigned_at")},
        audited_update({"$set": fields, "$push": {"history": {
            "status": fields.get("status", doc["status"]), "at": timestamp, "by": user["name"]}}},
            "Assignment changed", user, timestamp, previous_assignee=previous["name"],
            assignee=assignee["name"] if assignee else None, reason=body.reason),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order changed; reload and try again")
    return {"order": public_order(updated, user)}


@app.post("/api/admin/orders/{order_id}/assign")
def admin_assign_order(order_id: str, body: AdminAssignment, admin=Depends(admin_user), conn=Depends(connection)):
    if body.user_id == admin["id"]:
        assignee = admin
    else:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, role FROM users WHERE id = %s", (body.user_id,))
            assignee = cur.fetchone()
        if assignee is None or assignee["role"] != "planning":
            raise HTTPException(status_code=400, detail="Select a planning team member")
    timestamp = now()
    updated = order_store().find_one_and_update(
        {"order_id": order_id, "status": "submitted", "assigned_planner": None, "scanner_approved": True},
        audited_update({"$set": {"status": "planning_in_progress", "assigned_planner": {"id": assignee["id"], "name": assignee["name"]},
                  "assigned_at": timestamp, "assigned_by": {"id": admin["id"], "name": admin["name"]}},
         "$push": {"history": {"status": "planning_in_progress", "at": timestamp, "by": admin["name"]}}},
         "Planner assigned", admin, timestamp, assignee=assignee["name"],
         from_status="submitted", to_status="planning_in_progress"),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order already assigned or unavailable")
    return {"order": public_order(updated, admin)}

@app.post("/api/orders/{order_id}/status")
def change_status(order_id: str, body: StatusInput, user=Depends(current_user)):
    order = get_order(order_id, user)
    doc = workflow_view(order, body.batch_number)
    if any(issue.get("resolved_at") is None for issue in order.get("issues", [])):
        raise HTTPException(409, "Resolve all open issues before advancing this order")
    target = body.status
    if target == "plan_completed" and doc["status"] == "planning_in_progress" and (doc.get("assigned_planner") or {}).get("id") != user["id"]:
        raise HTTPException(status_code=403, detail="Only the assigned planner can complete the plan")
    if target == "cancelled":
        if order.get("batches"):
            raise HTTPException(409, "Cannot cancel an approved batch order")
        if user["role"] not in {"marketing", "clinic_admin", "clinician"}:
            raise HTTPException(status_code=403, detail="Marketing or clinic admin only")
        if doc["status"] not in ORDER_STEPS[:4] + SCANNER_STEPS + [DOCUMENT_REVIEW]:
            raise HTTPException(status_code=409, detail="Order cannot be cancelled after clinician approval")
    else:
        legacy_review_reset = (target == "plan_completed" and doc["status"] == "clinician_issues"
                               and user["role"] in CLINICAL_REVIEW_ROLES and not doc["issues"])
        clinical_approval = target == "clinician_approved" and user["role"] in CLINICAL_REVIEW_ROLES
        admin_plan = target == "plan_completed" and user["role"] == "admin" and (doc.get("assigned_planner") or {}).get("id") == user["id"]
        status_role = STATUS_ROLES.get(target)
        admin_production = user["role"] == "admin" and status_role == "production"
        qc_approval = target == "qc_approved" and user["role"] in QC_REVIEW_ROLES
        if not (legacy_review_reset or clinical_approval or qc_approval or admin_plan or admin_production or user["role"] == status_role):
            raise HTTPException(status_code=403, detail="Team cannot set this status")
        allowed = (legacy_review_reset or
                   (doc["status"] == "planning_in_progress" and target == "plan_completed") or
                   (doc["status"] == "plan_completed" and target == "clinician_approved") or
                   (doc["status"], target) in {
                       ("clinician_approved", "manufacturing_in_process"),
                       ("manufacturing_in_process", "manufactured"),
                       ("manufactured", "qc_approved"),
                   })
        if not allowed:
            raise HTTPException(status_code=409, detail="Invalid status transition")
        if target == "clinician_approved" and any(issue["resolved_at"] is None for issue in doc["issues"]):
            raise HTTPException(status_code=409, detail="Resolve clinician issues before approval")
        if target == "qc_approved" and any(issue["resolved_at"] is None for issue in doc["issues"]):
            raise HTTPException(status_code=409, detail="Resolve QC issues before approval")
    timestamp = now()
    guard = {"order_id": order_id, "status": doc["status"], "issue_revision": order.get("issue_revision")}
    if target == "plan_completed" and doc["status"] == "planning_in_progress":
        guard["assigned_planner.id"] = user["id"]
    update_fields = {"status": target, "updated_at": timestamp}
    if target == "plan_completed" and doc["status"] == "planning_in_progress":
        update_fields["plan_completed_at"] = timestamp
        if not order.get("batches"):
            if body.aligner_quantity is None:
                raise HTTPException(422, "Enter the required aligner quantity")
            update_fields["aligner_quantity"] = body.aligner_quantity
    if target == "clinician_approved" and doc.get("revision_approval_required"):
        if not case_clinician(order, user):
            raise HTTPException(403, "The case clinician must approve the revised plan")
        update_fields["revision_approval_required"] = False
    if target == "clinician_approved" and not order.get("batches"):
        total = doc.get("aligner_quantity")
        if total and not body.dispatch_mode:
            raise HTTPException(422, "Choose a dispatch method")
        if body.dispatch_mode == "batches":
            count = body.batch_count
            if not total or not count or count > total:
                raise HTTPException(422, "Batch count must be between one and the aligner quantity")
            size, remainder = divmod(total, count)
            update_fields.update(current_batch=1, batches=[
                {"quantity": size + (remainder if i == count - 1 else 0),
                 "status": target if i == 0 else "upcoming"} for i in range(count)])
        update_fields["dispatch_mode"] = body.dispatch_mode or "together"
    batch_transition(order, body.batch_number, target, update_fields, guard)
    updated = order_store().find_one_and_update(guard,
        audited_update({"$set": update_fields, "$push": {"history": {
            "status": target, "at": timestamp, "by": user["name"]}}}, "Status changed", user, timestamp,
            from_status=doc["status"], to_status=target, batch_number=body.batch_number),
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order changed; reload and try again")
    return {"order": public_order(updated, user)}


@app.post("/api/orders/{order_id}/documents", status_code=201)
async def upload_order_document(order_id: str, file: UploadFile = File(...), user=Depends(current_user),
                                checklist_id: str = Form(""), issue_id: str = Form(""),
                                category: str = Form("")):
    doc = get_order(order_id, user)
    if doc["status"] == "cancelled":
        raise HTTPException(status_code=409, detail="Order is cancelled")
    if isinstance(issue_id, str) and issue_id:
        issue = next((i for i in doc.get("issues", []) if i["id"] == issue_id), None)
        if issue is None:
            raise HTTPException(404, "Issue not found")
        if issue.get("raised_by_id") != user["id"]:
            raise HTTPException(403, "Only the issue author can attach files")
        if isinstance(checklist_id, str) and checklist_id:
            raise HTTPException(400, "Choose an issue or a checklist item")
    else:
        issue_id = ""
    if not isinstance(checklist_id, str):
        checklist_id = ""
    if not isinstance(category, str):
        category = ""
    if (category not in {"", "scan", "plan"} or (category and issue_id) or
            (category == "plan" and checklist_id)):
        raise HTTPException(status_code=400, detail="Document category does not match this upload")
    if checklist_id:
        if not can_prepare_documents(doc, user) or doc["status"] not in SCANNER_STEPS:
            raise HTTPException(status_code=403, detail="Checklist uploads require an editable case and a document preparer")
        item = next((i for i in doc.get("checklist", []) if i["id"] == checklist_id), None)
        if item is None or Path(file.filename or "").suffix.lower() not in item["extensions"]:
            raise HTTPException(status_code=400, detail="File type does not match the checklist item")
    allowed = {"application/pdf", "image/jpeg", "image/png", "model/stl", "application/sla", "application/octet-stream"}
    filename = (file.filename or "file").split("/")[-1].split("\\")[-1][:200]
    if file.content_type not in allowed or not filename.lower().endswith((".pdf", ".jpg", ".jpeg", ".png", ".stl")):
        raise HTTPException(status_code=400, detail="Use PDF, JPG, PNG, or STL")
    try:
        key, size, checksum = await save_upload(settings.data_dir / "orders", order_id, file)
    except ValueError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    meta = {"id": str(ObjectId()), "storage_key": key, "name": filename,
            "size": size, "sha256": checksum, "content_type": file.content_type,
            "at": now(), "by": user["name"], "role": user["role"], "checklist_id": checklist_id}
    if checklist_id or category:
        meta["category"] = "scan" if checklist_id else category
    if issue_id:
        meta["issue_id"] = issue_id
        if any(d.get("issue_id") == issue_id and d["name"] == filename and d.get("sha256") == checksum
               for d in doc.get("documents", [])):
            storage_path(settings.data_dir / "orders", key).unlink(missing_ok=True)
            return {"order": public_order(doc, user)}
    try:
        fields = {}
        if checklist_id:
            checklist = deepcopy(doc["checklist"])
            item = next(i for i in checklist if i["id"] == checklist_id)
            item["document_ids"].append(meta["id"])
            item["verified"] = False
            item["waiver"] = None
            fields["checklist"] = checklist
        result = order_store().update_one({"order_id": order_id, "status": doc["status"],
                                           "updated_at": doc["updated_at"],
                                           "review_revision": doc.get("review_revision")},
            audited_update({"$push": {"documents": meta}, "$set": fields, "$inc": {"review_revision": 1}},
                           "Document uploaded", user, meta["at"], document=filename))
        if result.matched_count != 1:
            raise HTTPException(status_code=409, detail="Order changed while uploading")
    except BaseException:
        storage_path(settings.data_dir / "orders", key).unlink(missing_ok=True)
        raise
    return {"order": public_order(get_order(order_id, user), user)}


@app.get("/api/orders/{order_id}/documents/{document_id}")
def download_order_document(order_id: str, document_id: str, user=Depends(current_user)):
    doc = get_order(order_id, user)
    meta = next((item for item in doc["documents"] if item["id"] == document_id), None)
    if meta is None:
        raise HTTPException(status_code=404, detail="Document not found")
    if key := meta.get("storage_key"):
        try:
            path = storage_path(settings.data_dir / "orders", key)
        except ValueError as exc:
            raise HTTPException(status_code=500, detail="Invalid document storage key") from exc
        if not path.is_file():
            raise HTTPException(status_code=404, detail="Stored document is missing")
        return FileResponse(path, media_type=meta["content_type"], filename=meta["name"])
    # Existing GridFS documents remain available until and after migration.
    stream = files.get(ObjectId(document_id))
    return StreamingResponse(stream, media_type=meta["content_type"], headers={
        "Content-Disposition": "attachment; filename*=UTF-8''" + quote(meta["name"])})


class DocumentCategoryInput(BaseModel):
    category: str


@app.patch("/api/orders/{order_id}/documents/{document_id}/category")
def classify_order_document(order_id: str, document_id: str, body: DocumentCategoryInput,
                            user=Depends(current_user)):
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only admins can classify existing documents")
    if body.category not in {"scan", "plan"}:
        raise HTTPException(status_code=422, detail="Choose Scan Documents or Plan Documents")
    doc = get_order(order_id, user)
    meta = next((item for item in doc.get("documents", []) if item["id"] == document_id), None)
    if meta is None:
        raise HTTPException(status_code=404, detail="Document not found")
    if document_category(meta, checklist_document_ids(doc)) is not None:
        raise HTTPException(status_code=409, detail="Only unclassified documents can be assigned")
    result = order_store().update_one(
        {"order_id": order_id, "documents.id": document_id,
         "updated_at": doc["updated_at"], "review_revision": doc.get("review_revision")},
        audited_update({"$set": {"documents.$.category": body.category}},
                       "Document classified", user, now(), document=meta["name"], category=body.category))
    if result.matched_count != 1:
        raise HTTPException(status_code=409, detail="Order changed; reload and try again")
    return order_detail(order_id, user)


@app.delete("/api/orders/{order_id}/documents/{document_id}", status_code=204)
def delete_order_document(order_id: str, document_id: str, user=Depends(current_user)):
    doc = get_order(order_id, user)
    meta = next((item for item in doc["documents"] if item["id"] == document_id), None)
    if meta is None:
        raise HTTPException(status_code=404, detail="Document not found")
    if user["role"] != meta["role"] and user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only the uploading team can delete this document")
    if meta.get("checklist_id") or document_id in checklist_document_ids(doc):
        raise HTTPException(status_code=409, detail="Checklist files are retained as history; update selected files instead")
    result = order_store().update_one({"order_id": order_id, "documents.id": document_id,
                                      "updated_at": doc["updated_at"], "review_revision": doc.get("review_revision")},
                                      audited_update({"$pull": {"documents": {"id": document_id}},
                                                      "$inc": {"review_revision": 1}},
                                                     "Document deleted", user, now(), document=meta["name"]))
    if result.modified_count != 1:
        raise HTTPException(status_code=409, detail="Document changed; reload and try again")
    if key := meta.get("storage_key"):
        storage_path(settings.data_dir / "orders", key).unlink(missing_ok=True)
    else:
        files.delete(ObjectId(document_id))

