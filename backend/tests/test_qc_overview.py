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
    def test_admin_production_queue_matches_production_team(self):
        orders = _Orders()
        with patch.object(main, "order_store", return_value=orders):
            for filters in ({}, {"status_group": "qc_issue_raised", "clinic_id": 3, "q": "ABC"}):
                main.list_orders(user={"role": "production"}, **filters)
                expected_query = orders.last_query
                main.list_orders(view="production", user={"role": "admin"}, **filters)
                self.assertEqual(orders.last_query, expected_query)
            self.assertEqual(main.lab_overview(user={"role": "admin"}),
                             main.lab_overview(user={"role": "production"}))

    def test_counts_pending_resolved_and_completed(self):
        with patch.object(main, "order_store", return_value=_Orders()):
            result = main.qc_overview(user={"role": "planning"})
        self.assertEqual(result["all_orders"], 5)
        self.assertEqual(result["qc_approval_pending"], 1)
        self.assertEqual(result["qc_issue_raised"], 1)
        self.assertEqual(result["qc_issue_resolved"], 1)
        self.assertEqual(result["qc_approval_completed"], 2)
        self.assertEqual(result["clinics"], [{"id": 3, "name": "ABC clinic"}])

    def test_resolved_filter_uses_issue_history_and_clinic(self):
        orders = _Orders()
        with patch.object(main, "order_store", return_value=orders):
            main.list_orders(status_group="qc_issue_resolved", clinic_id=3,
                             user={"role": "planning"})
        self.assertEqual(orders.last_query["clinic_id"], 3)
        self.assertEqual(orders.last_query["status"], {"$in": ["manufactured"]})
        self.assertEqual(orders.last_query["issues"]["$elemMatch"]["raised_to"], {"$in": ["production", "lab"]})

    def test_other_roles_cannot_read_qc_overview(self):
        with self.assertRaises(HTTPException) as caught:
            main.qc_overview(user={"role": "marketing"})
        self.assertEqual(caught.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
