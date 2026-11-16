"""Move existing patient data to PostgreSQL and link MongoDB orders.

Run database/setup.sql first, then run this script from the backend directory.
Safe to rerun. MongoDB patient documents are retained for backup until reviewed.
"""
import psycopg
from psycopg.rows import dict_row
from pymongo import MongoClient

from app.main import settings


def main():
    db = MongoClient(settings.mongodb_url)[settings.mongodb_database]
    migrated = 0
    old_ids = {}
    with psycopg.connect(settings.database_url, row_factory=dict_row) as conn:
        for order in db.orders.find({}):
            order_id = order["order_id"]
            with conn.cursor() as cur:
                cur.execute("SELECT patient_id FROM patient_orders WHERE order_id = %s", (order_id,))
                linked = cur.fetchone()
                old_patient = None
                if linked:
                    patient_id = linked["patient_id"]
                else:
                    old_patient = (db.patients.find_one({"patient_id": order["patient_id"]})
                                   if order.get("patient_id") else None)
                    clinic_id = order.get("clinic_id")
                    if clinic_id is None:
                        print(f"Skipping {order_id}: no clinic ID")
                        continue
                    cur.execute("SELECT id FROM clinics WHERE id = %s", (clinic_id,))
                    if cur.fetchone() is None:
                        print(f"Skipping {order_id}: clinic {clinic_id} does not exist")
                        continue
                    clinician_id = order.get("clinician_id") or (old_patient or {}).get("clinician_id")
                    if clinician_id is not None:
                        cur.execute("SELECT clinician_id FROM clinicians WHERE clinician_id = %s "
                                    "AND clinic_id = %s", (clinician_id, clinic_id))
                        if cur.fetchone() is None:
                            clinician_id = None
                    reference = order.get("clinic_patient_id") or (old_patient or {}).get("clinic_patient_id")
                    name = order.get("patient_name") or (old_patient or {}).get("name") or "Unknown"
                    mobile = order.get("patient_mobile_number") or (old_patient or {}).get("mobile_number") or ""
                    email = order.get("patient_email") or (old_patient or {}).get("email")
                    patient_id = old_ids.get(order.get("patient_id"))
                    if reference:
                        cur.execute("SELECT patient_id FROM patients WHERE clinic_id = %s "
                                    "AND clinic_patient_id = %s", (clinic_id, reference))
                        existing = cur.fetchone()
                        if existing:
                            patient_id = existing["patient_id"]
                    if patient_id is None:
                        cur.execute("INSERT INTO patients (clinic_patient_id, name, mobile_number, "
                                    "email, clinic_id, clinician_id) VALUES (%s, %s, %s, %s, %s, %s) "
                                    "RETURNING patient_id",
                                    (reference, name, mobile, email, clinic_id, clinician_id))
                        patient_id = cur.fetchone()["patient_id"]
                    if order.get("patient_id"):
                        old_ids[order["patient_id"]] = patient_id
                    cur.execute("INSERT INTO patient_orders (order_id, patient_id) VALUES (%s, %s) "
                                "ON CONFLICT (order_id) DO NOTHING", (order_id, patient_id))
                db.orders.update_one({"_id": order["_id"]}, {"$set": {
                    "patient_id": f"PAT-{patient_id:06d}",
                    "patient_mobile_number": order.get("patient_mobile_number") or "",
                    "patient_email": order.get("patient_email"),
                    "clinic_patient_id": order.get("clinic_patient_id") or
                                         (old_patient or {}).get("clinic_patient_id"),
                    "clinician_id": order.get("clinician_id")}})
            conn.commit()
            migrated += 1
    print(f"Linked {migrated} orders to PostgreSQL patients")


if __name__ == "__main__":
    main()
