from fastapi.staticfiles import StaticFiles
from app.main import app

# Register after all API routes so the packaged web client can share their origin.
app.mount("/", StaticFiles(directory="/opt/vclear/web", html=True), name="web")
