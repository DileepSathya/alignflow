import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app import main


class _Orders:
    def __init__(self, order=None):
        self.order = order

    def find_one_and_update(self, query, update, return_document=None):
        if self.order["status"] != query["status"]:
            return None
        self.order.update(update["$set"])
        self.order["history"].append(update["$push"]["history"])
        return self.order

    def aggregate(self, pipeline):
        if "$sort" in pipeline[-1]:
            return iter([{"_id": 3, "name": "ABC clinic"}])
        return iter([
            {"_id": "clinician_approved", "count": 1},
            {"_id": "manufacturing_in_process", "count": 1},
            {"_id": "qc_approved", "count": 2},
        ])

    def count_documents(self, query):
        self.last_query = query
        return 0

    def find(self, query):
        return self

    def sort(self, *_):
        return self

    def skip(self, *_):
        return self

    def limit(self, *_):
        return []


class LabWorkflowTests(unittest.TestCase):
    def test_manufacturing_requires_start_before_qc_handoff(self):
        order = {"order_id": "ORD-000001", "status": "clinician_approved",
                 "issues": [], "history": []}
        store = _Orders(order)
        with patch.object(main, "get_order", return_value=order), \
             patch.object(main, "order_store", return_value=store), \
             patch.object(main, "public_order", side_effect=lambda value: value):
            user = {"role": "lab", "name": "Maker"}
            with self.assertRaises(HTTPException) as caught:
                main.change_status(order["order_id"], main.StatusInput(status="manufactured"), user=user)
            self.assertEqual(caught.exception.status_code, 409)
            main.change_status(order["order_id"],
                               main.StatusInput(status="manufacturing_in_process"), user=user)
            self.assertEqual(order["status"], "manufacturing_in_process")
            main.change_status(order["order_id"], main.StatusInput(status="manufactured"), user=user)
            self.assertEqual(order["status"], "manufactured")

    def test_overview_and_status_filter(self):
        store = _Orders()
        with patch.object(main, "order_store", return_value=store):
            overview = main.lab_overview(user={"role": "lab"})
            main.list_orders(status_group="manufacturing_completed", clinic_id=3,
                             user={"role": "lab"})
        self.assertEqual(overview["all_orders"], 4)
        self.assertEqual(overview["manufacturing_in_process"], 1)
        self.assertEqual(overview["manufacturing_completed"], 2)
        self.assertEqual(store.last_query["clinic_id"], 3)
        self.assertIn("qc_approved", store.last_query["status"]["$in"])

    def test_qc_queue_excludes_manufacturing_in_process(self):
        store = _Orders()
        with patch.object(main, "order_store", return_value=store):
            main.list_orders(user={"role": "qc"})
        self.assertNotIn("manufacturing_in_process", store.last_query["status"]["$in"])


if __name__ == "__main__":
    unittest.main()
