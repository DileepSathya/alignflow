import unittest
from unittest.mock import patch

from app import main


class _Cursor:
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, query):
        assert "COUNT(*)" in query

    def fetchone(self):
        return {"count": 6}


class _Connection:
    def cursor(self):
        return _Cursor()


class _Orders:
    def aggregate(self, pipeline):
        assert pipeline[0]["$project"]["open_issues"]
        return iter([
            {"_id": "plan_completed", "count": 1, "open_issues": 0},
            {"_id": "qc_approved", "count": 2, "open_issues": 0},
            {"_id": "cancelled", "count": 2, "open_issues": 0},
        ])


class AdminOverviewTests(unittest.TestCase):
    def test_counts_all_orders_and_users(self):
        with patch.object(main, "order_store", return_value=_Orders()):
            result = main.admin_overview(admin={"role": "admin"}, conn=_Connection())
        self.assertEqual(result, {
            "total_orders": 5, "users": 6, "in_plan": 1,
            "in_manufacturing": 0, "in_qc": 0, "completed": 2,
            "cancelled": 2, "open_issues": 0,
        })


if __name__ == "__main__":
    unittest.main()
