import unittest
from unittest.mock import MagicMock, patch

from fastapi import HTTPException

from app import main


class AdminOrderCreationTests(unittest.TestCase):
    def setUp(self):
        self.admin = {"id": 7, "name": "Admin", "role": "admin"}
        self.body = main.OrderInput(request_id="admin-order-1", clinic_id=2,
                                    clinician_id=3, patient_name="Patient",
                                    patient_mobile_number="5551234")
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.side_effect = [
            {"clinic_name": "Clinic", "contact_number": "123", "email": None, "area": "West"},
            {"patient_id": 1, "clinic_patient_id": None, "name": "Patient",
             "mobile_number": "5551234"},
        ]
        self.cursor.fetchall.return_value = [{"clinician_id": 3}]

    @patch.object(main, "mongo")
    @patch.object(main, "order_store")
    def test_admin_creates_order_in_scanner_review(self, store, mongo):
        store.return_value.find_one.return_value = None
        mongo.counters.find_one_and_update.return_value = {"value": 1}
        order = main.create_order(self.body, self.admin, self.conn)["order"]
        self.assertEqual(order["created_by"], self.admin)
        self.assertEqual(order["status"], "scanner_review")
        self.assertIsNone(order["case_id"])
        self.assertEqual((order["clinic_id"], order["clinician_id"]), (2, 3))
        store.return_value.insert_one.assert_called_once()

    @patch.object(main, "mongo")
    @patch.object(main, "order_store")
    def test_case_id_round_trip(self, store, mongo):
        mongo.counters.find_one_and_update.return_value = {"value": 1}
        store.return_value.find_one.return_value = None
        records = list(self.cursor.fetchone.side_effect)
        for supplied, expected in [(None, None), ("", None), ("  ", None), (" 0042 ", "0042")]:
            with self.subTest(case_id=supplied):
                self.cursor.fetchone.side_effect = records
                self.body.case_id = supplied
                order = main.create_order(self.body, self.admin, self.conn)["order"]
                self.assertEqual(order["case_id"], expected)
                saved = store.return_value.insert_one.call_args.args[0]
                self.assertEqual(main.public_order(saved)["case_id"], expected)
        legacy = dict(saved)
        del legacy["case_id"]
        self.assertIsNone(main.public_order(legacy).get("case_id"))

    @patch.object(main, "order_store")
    @patch.object(main, "get_order")
    def test_edit_patient_case_id_only_affects_selected_order(self, get_order, store):
        get_order.return_value = {"_id": "example", "case_id": "old"}
        self.cursor.fetchone.side_effect = None
        self.cursor.fetchone.return_value = {"patient_id": 1}
        for change, expected in [({}, {}), ({"case_id": " 0042 "}, {"case_id": "0042"}),
                                 ({"case_id": None}, {"case_id": None})]:
            with self.subTest(change=change):
                body = main.PatientUpdate(patient_name="Patient", patient_mobile_number="5551234", **change)
                main.edit_patient("ORD-000001", body, self.admin, self.conn)
                target, update = store.return_value.update_one.call_args.args
                self.assertEqual(target, {"order_id": "ORD-000001"})
                self.assertEqual({k: v for k, v in update["$set"].items() if k == "case_id"}, expected)
                self.assertNotIn("case_id", store.return_value.update_many.call_args.args[1]["$set"])

    @patch.object(main, "order_store")
    def test_admin_must_choose_clinician_from_selected_clinic(self, store):
        store.return_value.find_one.return_value = None
        self.cursor.fetchall.return_value = [{"clinician_id": 4}]
        with self.assertRaises(HTTPException) as failure:
            main.create_order(self.body, self.admin, self.conn)
        self.assertEqual(failure.exception.status_code, 400)
        store.return_value.insert_one.assert_not_called()
