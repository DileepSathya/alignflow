import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app import main


class _Orders:
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

    def aggregate(self, pipeline):
        if "$match" in pipeline[0]:
            return iter([{"_id": 3, "name": "ABC clinic"}])
        return iter([
            {"_id": "submitted", "count": 1},
            {"_id": "qc_approved", "count": 2},
            {"_id": "cancelled", "count": 2},
        ])


class CadOverviewTests(unittest.TestCase):
    def test_status_counts_and_clinics(self):
        with patch.object(main, "order_store", return_value=_Orders()):
            result = main.cad_overview(user={"role": "cad"})
        self.assertEqual(result["all_orders"], 5)
        self.assertEqual(result["plan_pending"], 1)
        self.assertEqual(result["approved"], 2)
        self.assertEqual(result["cancelled"], 2)
        self.assertEqual(result["clinics"], [{"id": 3, "name": "ABC clinic"}])

    def test_other_roles_cannot_read_queue_overview(self):
        with self.assertRaises(HTTPException) as caught:
            main.cad_overview(user={"role": "marketing"})
        self.assertEqual(caught.exception.status_code, 403)

    def test_approved_tab_and_clinic_filter_reach_order_query(self):
        orders = _Orders()
        with patch.object(main, "order_store", return_value=orders):
            main.list_orders(status_group="approved", clinic_id=3,
                             user={"role": "cad"})
        self.assertEqual(orders.last_query["clinic_id"], 3)
        self.assertIn("qc_approved", orders.last_query["status"]["$in"])


if __name__ == "__main__":
    unittest.main()
