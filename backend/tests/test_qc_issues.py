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
            self.order.setdefault(key, []).append(value)
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
        return main.add_issue("ORD-000001", main.IssueInput(text="Remake tray", raised_to="production"),
                              user={"role": "planning", "name": "Reviewer"})

    def test_next_batch_waits_for_qc_approval(self):
        admin = {"id": 1, "name": "Admin", "role": "admin"}
        order_id = self.order["order_id"]
        self.order.update(status="planning_in_progress", assigned_planner=admin)

        def change(status, **kwargs):
            main.change_status(order_id, main.StatusInput(status=status, **kwargs), admin)

        change("plan_completed", aligner_quantity=21)
        with self.assertRaises(HTTPException):
            change("clinician_approved", dispatch_mode="batches", batch_count=22)
        change("clinician_approved", dispatch_mode="batches", batch_count=4)
        self.assertEqual([b["quantity"] for b in self.order["batches"]], [5, 5, 5, 6])
        for number in range(1, 5):
            if number > 1:
                change("plan_completed", batch_number=number)
                change("clinician_approved", batch_number=number)
            change("manufacturing_in_process", batch_number=number)
            change("manufactured", batch_number=number)
            self.assertEqual(self.order["current_batch"], number)
            self.assertEqual(self.order["status"], "manufactured")
            if number < 4:
                self.assertEqual(self.order["batches"][number]["status"], "upcoming")
                with self.assertRaises(HTTPException):
                    change("plan_completed", batch_number=number + 1)
            if number == 1:
                main.add_issue(order_id, main.IssueInput(text="Revise", raised_to="production", batch_number=1), admin)
                main.resolve_issue(order_id, self.order["issues"][0]["id"], admin)
                self.assertEqual(self.order["current_batch"], 1)
            change("qc_approved", batch_number=number)
            self.assertEqual(self.order["current_batch"], min(number + 1, 4))
            self.assertEqual(self.order["status"], "qc_approved" if number == 4 else "planning_in_progress")

    def test_qc_issue_routes_to_lab_and_blocks_approval(self):
        self.raise_qc_issue()
        self.assertEqual(self.order["status"], "qc_issues")
        self.assertEqual(self.order["issues"][0]["raised_to"], "production")
        with self.assertRaises(HTTPException) as caught:
            main.change_status("ORD-000001", main.StatusInput(status="qc_approved"),
                               user={"role": "planning", "name": "Reviewer"})
        self.assertEqual(caught.exception.status_code, 409)

    def test_only_lab_resolves_qc_issue_and_order_returns_to_qc(self):
        self.raise_qc_issue()
        issue_id = self.order["issues"][0]["id"]
        for role in ("planning", "marketing"):
            with self.subTest(role=role), self.assertRaises(HTTPException) as caught:
                main.resolve_issue("ORD-000001", issue_id, user={"role": role, "name": role})
            self.assertEqual(caught.exception.status_code, 403)
        main.resolve_issue("ORD-000001", issue_id, user={"role": "production", "name": "Maker"})
        self.assertEqual(self.order["status"], "manufactured")
        self.assertIsNotNone(self.order["issues"][0]["resolved_at"])
        main.change_status("ORD-000001", main.StatusInput(status="qc_approved"),
                           user={"role": "planning", "name": "Reviewer"})
        self.assertEqual(self.order["status"], "qc_approved")

    def test_qc_can_only_raise_at_manufactured_stage_for_lab(self):
        with self.assertRaises(HTTPException) as caught:
            main.add_issue("ORD-000001", main.IssueInput(text="Wrong team", raised_to="planning"),
                           user={"role": "planning", "name": "Reviewer"})
        self.assertEqual(caught.exception.status_code, 409)
        self.order["status"] = "qc_approved"
        with self.assertRaises(HTTPException) as caught:
            self.raise_qc_issue()
        self.assertEqual(caught.exception.status_code, 409)

    def test_qc_approval_is_final(self):
        main.change_status("ORD-000001", main.StatusInput(status="qc_approved"),
                           user={"role": "planning", "name": "Reviewer"})
        with self.assertRaises(HTTPException) as caught:
            main.change_status("ORD-000001", main.StatusInput(status="manufacture_completed"),
                               user={"role": "production", "name": "Maker"})
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(self.order["status"], "qc_approved")

    def test_marketing_cannot_raise_qc_issue_but_can_raise_clinician_feedback(self):
        with self.assertRaises(HTTPException) as caught:
            main.add_issue("ORD-000001", main.IssueInput(text="Problem", raised_to="production"),
                           user={"role": "marketing", "name": "Marketer"})
        self.assertEqual(caught.exception.status_code, 409)
        self.order["status"] = "plan_completed"
        main.add_issue("ORD-000001", main.IssueInput(text="Clinician feedback", raised_to="planning"),
                       user={"role": "marketing", "name": "Marketer"})
        self.assertEqual(self.order["status"], "clinician_issues")
        self.assertEqual(self.order["issues"][0]["raised_to"], "planning")

    def test_admin_can_manufacture_and_resolve_production_issue(self):
        admin = {"role": "admin", "name": "Administrator", "id": 1}
        self.order["status"] = "clinician_approved"
        for status in ("manufacturing_in_process", "manufactured"):
            main.change_status("ORD-000001", main.StatusInput(status=status), user=admin)
            self.assertEqual(self.order["status"], status)
        main.add_issue("ORD-000001", main.IssueInput(text="Remake tray", raised_to="production"), admin)
        main.resolve_issue("ORD-000001", self.order["issues"][0]["id"], user=admin)
        self.assertEqual(self.order["status"], "manufactured")
        self.assertEqual(self.order["history"][-1]["by"], admin["name"])
        main.change_status("ORD-000001", main.StatusInput(status="qc_approved"), user=admin)
        self.assertEqual(self.order["status"], "qc_approved")

    def test_production_can_review_and_approve_after_resolution(self):
        maker = {"role": "production", "name": "Maker"}
        main.add_issue("ORD-000001", main.IssueInput(text="Remake tray", raised_to="production"), maker)
        approval = main.StatusInput(status="qc_approved")
        with self.assertRaises(HTTPException) as caught:
            main.change_status("ORD-000001", approval, maker)
        self.assertEqual(caught.exception.status_code, 409)
        main.resolve_issue("ORD-000001", self.order["issues"][0]["id"], maker)
        main.change_status("ORD-000001", approval, maker)
        self.assertEqual(self.order["history"][-1]["by"], "Maker")
        self.assertEqual(self.order["status"], "qc_approved")

    def test_admin_can_raise_clinician_issue_and_approve_after_resolution(self):
        admin = {"role": "admin", "name": "Administrator", "id": 1}
        approval = main.StatusInput(status="clinician_approved")
        self.order["status"] = "plan_completed"
        main.add_issue("ORD-000001", main.IssueInput(text="Revise plan", raised_to="planning"), admin)
        self.assertEqual(self.order["status"], "clinician_issues")
        issue = self.order["issues"][0]
        self.assertEqual(issue["raised_to"], "planning")
        self.assertEqual(issue["by"], "Administrator")
        with self.assertRaises(HTTPException) as caught:
            main.change_status("ORD-000001", approval, admin)
        self.assertEqual(caught.exception.status_code, 409)
        main.resolve_issue("ORD-000001", issue["id"], {"role": "planning", "name": "Planner"})
        main.change_status("ORD-000001", approval, admin)
        self.assertEqual(self.order["status"], "clinician_approved")
        self.assertEqual(self.order["history"][-1]["by"], "Administrator")

    def test_admin_can_return_legacy_order_to_clinical_review(self):
        self.order["status"] = "clinician_issues"
        main.change_status("ORD-000001", main.StatusInput(status="plan_completed"),
                           {"role": "admin", "name": "Administrator", "id": 1})
        self.assertEqual(self.order["status"], "plan_completed")


if __name__ == "__main__":
    unittest.main()
