import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app import main


class _Orders:
    def aggregate(self, pipeline):
        if "$sort" in pipeline[-1]:
            return iter([{"_id": 3, "name": "ABC clinic"}])
        return iter([
            {"_id": "manufactured", "count": 2},
            {"_id": "qc_issues", "count": 1},
            {"_id": "qc_approved", "count": 2},
        ])

    def count_documents(self, query):
        self.last_query = query
        return 1

    def find(self, query):
        return self

    def sort(self, *_):
        return self

    def skip(self, *_):
        return self

    def limit(self, *_):
        return []


class QcOverviewTests(unittest.TestCase):
    def test_counts_pending_resolved_and_completed(self):
        with patch.object(main, "order_store", return_value=_Orders()):
            result = main.qc_overview(user={"role": "qc"})
        self.assertEqual(result["all_orders"], 5)
        self.assertEqual(result["qc_approval_pending"], 1)
        self.assertEqual(result["issue_raised"], 1)
        self.assertEqual(result["issue_resolved"], 1)
        self.assertEqual(result["approval_completed"], 2)
        self.assertEqual(result["clinics"], [{"id": 3, "name": "ABC clinic"}])

    def test_resolved_filter_uses_issue_history_and_clinic(self):
        orders = _Orders()
        with patch.object(main, "order_store", return_value=orders):
            main.list_orders(status_group="issue_resolved", clinic_id=3,
                             user={"role": "qc"})
        self.assertEqual(orders.last_query["clinic_id"], 3)
        self.assertEqual(orders.last_query["status"], {"$in": ["manufactured"]})
        self.assertEqual(orders.last_query["issues"]["$elemMatch"]["raised_to"], "lab")

    def test_other_roles_cannot_read_qc_overview(self):
        with self.assertRaises(HTTPException) as caught:
            main.qc_overview(user={"role": "lab"})
        self.assertEqual(caught.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
