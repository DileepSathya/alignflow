from datetime import datetime, timedelta, timezone
import secrets
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from pymongo import MongoClient, ReturnDocument, ASCENDING, DESCENDING
from pymongo.errors import DuplicateKeyError
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure
from bson import ObjectId
from fastapi import File, UploadFile
from fastapi.responses import StreamingResponse, FileResponse
from fastapi.responses import JSONResponse
from gridfs import GridFS
from urllib.parse import quote
from app.order_storage import save_upload, storage_path


class Settings(BaseSettings):
    database_url: str
    mongodb_url: str = "mongodb://localhost:27017"
    mongodb_database: str = "alignflow"
    data_dir: Path = Path(__file__).resolve().parents[2] / "data"
    cors_origins: str = "http://localhost:8080,http://127.0.0.1:8080"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
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
        _orders_indexed = True
    return orders
app = FastAPI(title="AlignFlow API")


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


class LoginInput(BaseModel):
    username: str
    password: str


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
        if value not in {"marketing", "cad", "lab", "qc"}:
            raise ValueError("Choose a valid team role")
        return value


class ClinicInput(BaseModel):
    clinic_name: str = Field(min_length=1)
    dentist_name: str = Field(min_length=1)
    contact_number: str = Field(min_length=1)
    email: str | None = None
    area: str = Field(min_length=1)

    @field_validator("clinic_name", "dentist_name", "contact_number", "area")
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
    return {key: user[key] for key in ("id", "username", "name", "role", "created_at")}


def current_user(authorization: str | None = Header(default=None), conn=Depends(connection)) -> dict:
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
    return user


def admin_user(user=Depends(current_user)) -> dict:
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
    return user


def marketing_user(user=Depends(current_user)) -> dict:
    if user["role"] != "marketing":
        raise HTTPException(status_code=403, detail="Marketing team only")
    return user


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/api/login")
def login(body: LoginInput, conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM users WHERE lower(username) = lower(%s) AND password = %s",
            (body.username.strip(), body.password),
        )
        user = cur.fetchone()
        if user is None:
            raise HTTPException(status_code=401, detail="Invalid username or password")
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
        cur.execute("SELECT id, username, name, role, created_at FROM users ORDER BY created_at DESC, id DESC")
        return {"users": cur.fetchall()}


@app.post("/api/users", status_code=status.HTTP_201_CREATED)
def create_user(body: UserInput, admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM users WHERE lower(username) = lower(%s)", (body.username,))
        if cur.fetchone():
            raise HTTPException(status_code=409, detail="That username is already taken")
        cur.execute(
            "INSERT INTO users (username, password, name, role) VALUES (%s, %s, %s, %s) "
            "RETURNING id, username, name, role, created_at",
            (body.username, body.password, body.name, body.role),
        )
        return {"user": cur.fetchone()}


@app.delete("/api/users/{user_id}", status_code=204)
def delete_user(user_id: int, admin=Depends(admin_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT role FROM users WHERE id = %s", (user_id,))
        user = cur.fetchone()
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        if user["role"] == "admin":
            raise HTTPException(status_code=400, detail="The admin account cannot be deleted")
        cur.execute("DELETE FROM users WHERE id = %s", (user_id,))


@app.get("/api/clinics")
def list_clinics(user=Depends(marketing_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM clinics ORDER BY clinic_name, id")
        return {"clinics": cur.fetchall()}


@app.post("/api/clinics", status_code=status.HTTP_201_CREATED)
def create_clinic(body: ClinicInput, user=Depends(marketing_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO clinics (clinic_name, dentist_name, contact_number, email, area) "
            "VALUES (%s, %s, %s, %s, %s) RETURNING *",
            (body.clinic_name, body.dentist_name, body.contact_number, body.email, body.area),
        )
        return {"clinic": cur.fetchone()}


@app.put("/api/clinics/{clinic_id}")
def update_clinic(clinic_id: int, body: ClinicInput, user=Depends(marketing_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE clinics SET clinic_name = %s, dentist_name = %s, contact_number = %s, "
            "email = %s, area = %s, updated_at = NOW() WHERE id = %s RETURNING *",
            (body.clinic_name, body.dentist_name, body.contact_number, body.email, body.area, clinic_id),
        )
        clinic = cur.fetchone()
    if clinic is None:
        raise HTTPException(status_code=404, detail="Clinic not found")
    return {"clinic": clinic}


@app.delete("/api/clinics/{clinic_id}", status_code=204)
def delete_clinic(clinic_id: int, user=Depends(marketing_user), conn=Depends(connection)):
    with conn.cursor() as cur:
        cur.execute("DELETE FROM clinics WHERE id = %s RETURNING id", (clinic_id,))
        if cur.fetchone() is None:
            raise HTTPException(status_code=404, detail="Clinic not found")


class OrderInput(BaseModel):
    request_id: str = Field(min_length=8, max_length=100)
    patient_name: str = Field(min_length=1, max_length=160)
    age: int | None = Field(default=None, ge=0, le=120)
    clinic_id: int
    notes: str = Field(default="", max_length=10000)


class PatientUpdate(BaseModel):
    patient_name: str = Field(min_length=1, max_length=160)
    age: int | None = Field(default=None, ge=0, le=120)
    notes: str = Field(default="", max_length=10000)


class CommentInput(BaseModel):
    text: str = Field(min_length=1, max_length=5000)


class IssueInput(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    raised_to: str = Field(default="cad", pattern=r"^(marketing|cad|lab|qc)$")


class StatusInput(BaseModel):
    status: str


ORDER_STEPS = ["submitted", "plan_completed", "clinician_issues", "clinician_approved",
               "manufactured", "qc_approved", "manufacture_completed"]
STATUS_ROLES = {"plan_completed": "cad", "clinician_issues": "cad",
                "clinician_approved": "cad", "manufactured": "lab",
                "qc_approved": "qc", "manufacture_completed": "lab"}


def now():
    return datetime.now(timezone.utc)


def public_order(doc):
    result = {k: v for k, v in doc.items() if k not in {"_id", "request_id"}}
    result["id"] = str(doc["_id"])
    result["documents"] = [{k: v for k, v in item.items() if k != "storage_key"}
                           for item in doc.get("documents", [])]
    for key in ("created_at", "updated_at"):
        if result.get(key):
            result[key] = result[key].isoformat() + "Z" if result[key].tzinfo is None else result[key].isoformat()
    for key in ("history", "comments", "issues", "documents"):
        for item in result.get(key, []):
            for time_key in ("at", "resolved_at"):
                if isinstance(item.get(time_key), datetime):
                    item[time_key] = item[time_key].isoformat() + "Z" if item[time_key].tzinfo is None else item[time_key].isoformat()
    return result


def get_order(order_id: str):
    doc = order_store().find_one({"order_id": order_id})
    if doc is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return doc


@app.post("/api/orders", status_code=201)
def create_order(body: OrderInput, user=Depends(marketing_user), conn=Depends(connection)):
    existing = order_store().find_one({"request_id": body.request_id})
    if existing:
        if existing["created_by"]["id"] != user["id"]:
            raise HTTPException(status_code=409, detail="Request ID already used")
        return {"order": public_order(existing)}
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM clinics WHERE id = %s", (body.clinic_id,))
        clinic = cur.fetchone()
    if clinic is None:
        raise HTTPException(status_code=400, detail="Choose an existing clinic")
    sequence = mongo.counters.find_one_and_update(
        {"_id": "orders"}, {"$inc": {"value": 1}}, upsert=True,
        return_document=ReturnDocument.AFTER)["value"]
    timestamp = now()
    doc = {"order_id": f"ORD-{sequence:06d}", "request_id": body.request_id,
           "patient_name": body.patient_name.strip(), "age": body.age, "notes": body.notes.strip(),
           "clinic_id": body.clinic_id,
           "clinic": {"name": clinic["clinic_name"], "dentist": clinic["dentist_name"],
                      "contact": clinic["contact_number"], "email": clinic["email"], "area": clinic["area"]},
           "status": "submitted", "created_at": timestamp, "updated_at": timestamp,
           "created_by": {"id": user["id"], "name": user["name"], "role": user["role"]},
           "history": [{"status": "submitted", "at": timestamp, "by": user["name"]}],
           "comments": [], "issues": [], "documents": []}
    try:
        doc["_id"] = order_store().insert_one(doc).inserted_id
    except DuplicateKeyError:
        existing = order_store().find_one({"request_id": body.request_id})
        if existing and existing["created_by"]["id"] == user["id"]:
            return {"order": public_order(existing)}
        raise HTTPException(status_code=409, detail="Duplicate order request")
    return {"order": public_order(doc)}


@app.get("/api/orders")
def list_orders(q: str = "", status_filter: str = "", page: int = 1, limit: int = 25,
                user=Depends(current_user)):
    if page < 1 or not 1 <= limit <= 100:
        raise HTTPException(status_code=400, detail="Invalid page or limit")
    query = {}
    if status_filter:
        query["status"] = status_filter
    if q.strip():
        import re
        pattern = re.escape(q.strip()[:100])
        query["$or"] = [{field: {"$regex": pattern, "$options": "i"}}
                        for field in ("order_id", "patient_name", "clinic.name")]
    collection = order_store()
    total = collection.count_documents(query)
    rows = collection.find(query).sort("created_at", DESCENDING).skip((page - 1) * limit).limit(limit)
    return {"orders": [public_order(row) for row in rows], "total": total, "page": page}


@app.get("/api/orders/{order_id}")
def order_detail(order_id: str, user=Depends(current_user)):
    return {"order": public_order(get_order(order_id))}


@app.put("/api/orders/{order_id}/patient")
def edit_patient(order_id: str, body: PatientUpdate, user=Depends(marketing_user)):
    get_order(order_id)
    order_store().update_one({"order_id": order_id}, {"$set": {
        "patient_name": body.patient_name.strip(), "age": body.age,
        "notes": body.notes.strip(), "updated_at": now()}})
    return {"order": public_order(get_order(order_id))}


@app.post("/api/orders/{order_id}/comments", status_code=201)
def add_comment(order_id: str, body: CommentInput, user=Depends(current_user)):
    get_order(order_id)
    order_store().update_one({"order_id": order_id}, {"$push": {"comments": {
        "id": str(ObjectId()), "text": body.text.strip(), "at": now(),
        "by": user["name"], "role": user["role"]}}, "$set": {"updated_at": now()}})
    return {"order": public_order(get_order(order_id))}


@app.post("/api/orders/{order_id}/issues", status_code=201)
def add_issue(order_id: str, body: IssueInput, user=Depends(current_user)):
    doc = get_order(order_id)
    if doc["status"] == "cancelled":
        raise HTTPException(status_code=409, detail="Order is cancelled")
    order_store().update_one({"order_id": order_id}, {"$push": {"issues": {
        "id": str(ObjectId()), "text": body.text.strip(), "at": now(),
        "by": user["name"], "raised_to": body.raised_to, "resolved_at": None}},
        "$set": {"updated_at": now()}})
    return {"order": public_order(get_order(order_id))}


@app.post("/api/orders/{order_id}/issues/{issue_id}/resolve")
def resolve_issue(order_id: str, issue_id: str, user=Depends(current_user)):
    doc = get_order(order_id)
    issue = next((item for item in doc["issues"] if item["id"] == issue_id), None)
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if user["role"] != issue["raised_to"] and user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Issue belongs to another team")
    order_store().update_one({"order_id": order_id, "issues.id": issue_id},
                              {"$set": {"issues.$.resolved_at": now(), "updated_at": now()}})
    return {"order": public_order(get_order(order_id))}


@app.post("/api/orders/{order_id}/status")
def change_status(order_id: str, body: StatusInput, user=Depends(current_user)):
    doc = get_order(order_id)
    target = body.status
    if target == "cancelled":
        if user["role"] != "marketing":
            raise HTTPException(status_code=403, detail="Marketing team only")
        if doc["status"] not in ORDER_STEPS[:3]:
            raise HTTPException(status_code=409, detail="Order cannot be cancelled after clinician approval")
    else:
        if target not in STATUS_ROLES or user["role"] != STATUS_ROLES[target]:
            raise HTTPException(status_code=403, detail="Team cannot set this status")
        if doc["status"] == "cancelled" or ORDER_STEPS.index(target) != ORDER_STEPS.index(doc["status"]) + 1:
            raise HTTPException(status_code=409, detail="Invalid status transition")
    timestamp = now()
    updated = order_store().find_one_and_update({"order_id": order_id, "status": doc["status"]},
        {"$set": {"status": target, "updated_at": timestamp}, "$push": {"history": {
            "status": target, "at": timestamp, "by": user["name"]}}},
        return_document=ReturnDocument.AFTER)
    if updated is None:
        raise HTTPException(status_code=409, detail="Order changed; reload and try again")
    return {"order": public_order(updated)}


@app.post("/api/orders/{order_id}/documents", status_code=201)
async def upload_order_document(order_id: str, file: UploadFile = File(...), user=Depends(current_user)):
    doc = get_order(order_id)
    if doc["status"] == "cancelled":
        raise HTTPException(status_code=409, detail="Order is cancelled")
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
            "at": now(), "by": user["name"], "role": user["role"]}
    try:
        result = order_store().update_one({"order_id": order_id, "status": {"$ne": "cancelled"}},
            {"$push": {"documents": meta}, "$set": {"updated_at": now()}})
        if result.matched_count != 1:
            raise HTTPException(status_code=409, detail="Order changed while uploading")
    except BaseException:
        storage_path(settings.data_dir / "orders", key).unlink(missing_ok=True)
        raise
    return {"order": public_order(get_order(order_id))}


@app.get("/api/orders/{order_id}/documents/{document_id}")
def download_order_document(order_id: str, document_id: str, user=Depends(current_user)):
    doc = get_order(order_id)
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


@app.delete("/api/orders/{order_id}/documents/{document_id}", status_code=204)
def delete_order_document(order_id: str, document_id: str, user=Depends(current_user)):
    doc = get_order(order_id)
    meta = next((item for item in doc["documents"] if item["id"] == document_id), None)
    if meta is None:
        raise HTTPException(status_code=404, detail="Document not found")
    if user["role"] != meta["role"] and user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only the uploading team can delete this document")
    result = order_store().update_one({"order_id": order_id, "documents.id": document_id},
                                      {"$pull": {"documents": {"id": document_id}}})
    if result.modified_count != 1:
        raise HTTPException(status_code=409, detail="Document changed; reload and try again")
    if key := meta.get("storage_key"):
        storage_path(settings.data_dir / "orders", key).unlink(missing_ok=True)
    else:
        files.delete(ObjectId(document_id))
