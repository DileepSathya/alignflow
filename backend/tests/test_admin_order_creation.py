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
        self.assertEqual((order["clinic_id"], order["clinician_id"]), (2, 3))
        store.return_value.insert_one.assert_called_once()

    @patch.object(main, "order_store")
    def test_admin_must_choose_clinician_from_selected_clinic(self, store):
        store.return_value.find_one.return_value = None
        self.cursor.fetchall.return_value = [{"clinician_id": 4}]
        with self.assertRaises(HTTPException) as failure:
            main.create_order(self.body, self.admin, self.conn)
        self.assertEqual(failure.exception.status_code, 400)
        store.return_value.insert_one.assert_not_called()
