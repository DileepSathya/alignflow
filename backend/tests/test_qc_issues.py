import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app import main


class FakeOrders:
    def __init__(self, order):
        self.order = order

    def find_one_and_update(self, query, update, return_document=None):
        if self.order["status"] != query["status"]:
            return None
        if "issues" in query:
            expected = query["issues"]["$elemMatch"]
            if not any(issue["id"] == expected["id"] and issue["resolved_at"] is None
                       for issue in self.order["issues"]):
                return None
        for key, value in update.get("$set", {}).items():
            if key == "issues.$.resolved_at":
                next(issue for issue in self.order["issues"] if issue["id"] == expected["id"])["resolved_at"] = value
            else:
                self.order[key] = value
        for key, value in update.get("$push", {}).items():
            self.order[key].append(value)
        return self.order


class QcIssueTests(unittest.TestCase):
    def setUp(self):
        self.order = {"order_id": "ORD-000001", "status": "manufactured", "issues": [], "history": []}
        self.store = FakeOrders(self.order)
        self.patches = [
            patch.object(main, "get_order", return_value=self.order),
            patch.object(main, "order_store", return_value=self.store),
            patch.object(main, "public_order", side_effect=lambda order: order),
        ]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def raise_qc_issue(self):
        return main.add_issue("ORD-000001", main.IssueInput(text="Remake tray", raised_to="lab"),
                              user={"role": "qc", "name": "Reviewer"})

    def test_qc_issue_routes_to_lab_and_blocks_approval(self):
        self.raise_qc_issue()
        self.assertEqual(self.order["status"], "qc_issues")
        self.assertEqual(self.order["issues"][0]["raised_to"], "lab")
        with self.assertRaises(HTTPException) as caught:
            main.change_status("ORD-000001", main.StatusInput(status="qc_approved"),
                               user={"role": "qc", "name": "Reviewer"})
        self.assertEqual(caught.exception.status_code, 409)

    def test_only_lab_resolves_qc_issue_and_order_returns_to_qc(self):
        self.raise_qc_issue()
        issue_id = self.order["issues"][0]["id"]
        for role in ("qc", "cad", "marketing", "admin"):
            with self.subTest(role=role), self.assertRaises(HTTPException) as caught:
                main.resolve_issue("ORD-000001", issue_id, user={"role": role, "name": role})
            self.assertEqual(caught.exception.status_code, 403)
        main.resolve_issue("ORD-000001", issue_id, user={"role": "lab", "name": "Maker"})
        self.assertEqual(self.order["status"], "manufactured")
        self.assertIsNotNone(self.order["issues"][0]["resolved_at"])
        main.change_status("ORD-000001", main.StatusInput(status="qc_approved"),
                           user={"role": "qc", "name": "Reviewer"})
        self.assertEqual(self.order["status"], "qc_approved")

    def test_qc_can_only_raise_at_manufactured_stage_for_lab(self):
        with self.assertRaises(HTTPException) as caught:
            main.add_issue("ORD-000001", main.IssueInput(text="Wrong team", raised_to="cad"),
                           user={"role": "qc", "name": "Reviewer"})
        self.assertEqual(caught.exception.status_code, 409)
        self.order["status"] = "qc_approved"
        with self.assertRaises(HTTPException) as caught:
            self.raise_qc_issue()
        self.assertEqual(caught.exception.status_code, 409)

    def test_lab_cannot_raise_and_marketing_flow_still_works(self):
        with self.assertRaises(HTTPException) as caught:
            main.add_issue("ORD-000001", main.IssueInput(text="Problem", raised_to="lab"),
                           user={"role": "lab", "name": "Maker"})
        self.assertEqual(caught.exception.status_code, 403)
        self.order["status"] = "plan_completed"
        main.add_issue("ORD-000001", main.IssueInput(text="Clinician feedback", raised_to="cad"),
                       user={"role": "marketing", "name": "Marketer"})
        self.assertEqual(self.order["status"], "clinician_issues")
        self.assertEqual(self.order["issues"][0]["raised_to"], "cad")


if __name__ == "__main__":
    unittest.main()
