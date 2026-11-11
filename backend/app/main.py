from datetime import datetime, timedelta, timezone
import secrets

import psycopg
from psycopg.rows import dict_row
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    cors_origins: str = "http://localhost:8080,http://127.0.0.1:8080"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
app = FastAPI(title="AlignFlow API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()],
    allow_credentials=False,
    allow_methods=["GET", "POST", "DELETE"],
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
