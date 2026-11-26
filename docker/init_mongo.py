from pathlib import Path

from pymongo import MongoClient

with MongoClient("mongodb://127.0.0.1:27018") as client:
    admin = client.admin
    command = "updateUser" if admin.command("usersInfo", "alignflow")["users"] else "createUser"
    admin.command(
        command, "alignflow",
        pwd=Path("/storage/mongo-password").read_text().strip(),
        roles=[{"role": "readWrite", "db": "alignflow"}],
    )
