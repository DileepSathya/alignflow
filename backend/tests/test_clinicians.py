import unittest

from unittest.mock import MagicMock, patch

from fastapi import HTTPException
from app import main


class _Cursor:
    def __init__(self):
        self.rows = []
        self.inserted_id = 10
        self.kept_ids = None

    def execute(self, query, params):
        if query.startswith("SELECT clinician_id"):
            self.rows = [{"clinician_id": value} for value in params[1]]
        elif query.startswith("SELECT name, account_id"):
            self.rows = [{"name": "Doctor", "account_id": None}]
        elif query.startswith("INSERT INTO users"):
            self.rows = [{"id": 500}]
        elif query.startswith("INSERT INTO clinicians"):
            self.rows = [{"clinician_id": self.inserted_id}]
            self.inserted_id += 1
        elif query.startswith("DELETE FROM clinicians"):
            self.kept_ids = params[1]

    def fetchone(self):
        return self.rows[0]

    def fetchall(self):
        return self.rows


class ClinicianSaveTests(unittest.TestCase):
    def test_new_clinicians_are_kept_after_insert(self):
        cursor = _Cursor()
        people = [
            main.ClinicianInput(name="A", mobile_number="111", username="doctor_a", password="example123"),
            main.ClinicianInput(name="B", mobile_number="222", username="doctor_b", password="example456"),
        ]

        main.save_clinicians(cursor, 3, people)

        self.assertEqual(cursor.kept_ids, [10, 11])

    def test_existing_and_new_clinicians_are_kept(self):
        cursor = _Cursor()
        people = [
            main.ClinicianInput(clinician_id=4, name="A", mobile_number="111"),
            main.ClinicianInput(name="B", mobile_number="222", username="doctor_b", password="example456"),
        ]

        main.save_clinicians(cursor, 3, people)

        self.assertEqual(cursor.kept_ids, [4, 10])


class ClinicianAccessTests(unittest.TestCase):
    user = {"role": "clinician", "clinic_id": 3, "clinician_id": 7, "name": "Doctor", "id": 5}

    def test_personal_dashboard_and_list_scope(self):
        scope = {"clinic_id": 3, "clinician_id": 7}
        with patch.object(main, "order_store") as collection:
            main.clinic_overview(self.user)
            self.assertEqual(collection().find.call_args.args[0], scope)
            main.list_orders(user=self.user)
            collection().count_documents.assert_called_once_with(scope)
            with self.assertRaises(HTTPException):
                main.list_orders(user=self.user, clinician_id=8)

    def test_direct_order_access_and_admin_scope(self):
        with patch.object(main, "order_store") as collection:
            for clinic_id, clinician_id in [(3, 8), (4, 7)]:
                collection().find_one.return_value = {"clinic_id": clinic_id, "clinician_id": clinician_id}
                with self.assertRaises(HTTPException) as denied:
                    main.get_order("ORD-1", self.user)
                self.assertEqual(denied.exception.status_code, 404)
            collection().find_one.return_value = {"clinic_id": 3, "clinician_id": 8}
            self.assertEqual(main.get_order("ORD-1", dict(self.user, role="clinic_admin"))["clinician_id"], 8)

    def test_create_rejects_another_clinician_or_clinic(self):
        for clinic_id, clinician_id in [(3, 8), (4, 7)]:
            with self.assertRaises(HTTPException) as denied:
                main.create_order(MagicMock(clinic_id=clinic_id, clinician_id=clinician_id), self.user)
            self.assertEqual(denied.exception.status_code, 403)

    def test_login_provisioning_hashes_password_and_reports_conflicts(self):
        person = main.ClinicianInput(name="A", mobile_number="1", username=" doctor ", password="pass1234")
        cur = MagicMock()
        cur.fetchone.side_effect = [{"name": "A", "account_id": None}, None]
        with self.assertRaises(HTTPException) as conflict:
            main.provision_clinician(cur, 3, 7, person)
        self.assertEqual(conflict.exception.status_code, 409)
        username, hashed, name, role, clinic_id = cur.execute.call_args.args[1]
        self.assertEqual((username, name, role, clinic_id), ("doctor", "A", "clinician", 3))
        self.assertTrue(main.verify_password(person.password, hashed))
        self.assertNotEqual(hashed, person.password)


if __name__ == "__main__":
    unittest.main()
