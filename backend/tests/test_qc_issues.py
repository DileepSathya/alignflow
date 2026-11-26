import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app import main


class FakeOrders:
    def __init__(self, order):
        self.order = order

    def find_one_and_update(self, query, update, return_document=None):
        if "status" in query and self.order["status"] != query["status"]:
            return None
        if "issue_revision" in query and self.order.get("issue_revision") != query["issue_revision"]:
            return None
        if "issues" in query:
            expected = query["issues"]["$elemMatch"]
            issue = next((i for i in self.order["issues"] if all(i.get(k) == v for k, v in expected.items())), None)
            if not issue:
                return None
        for key, value in update.get("$set", {}).items():
            if key.startswith("issues.$."):
                issue[key.removeprefix("issues.$.")] = value
            else:
                self.order[key] = value
        for key, amount in update.get("$inc", {}).items():
            self.order[key] = self.order.get(key, 0) + amount
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
            patch.object(main, "public_order", side_effect=lambda order, user: order),
        ]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def resolve(self, issue_id, role, revision=False, **profile):
        user = {"name": role, "role": role, **profile}
        main.resolve_issue(self.order["order_id"], issue_id, user,
                           main.IssueResolution(requires_plan_revision=revision))

    def raise_qc_issue(self):
        return main.add_issue("ORD-000001", main.IssueInput(text="Remake tray", raised_to="production"),
                              user={"role": "planning", "name": "Reviewer"})

    def test_batch_revision_reaches_clinician_queue_and_approval(self):
        from datetime import datetime
        case = self.order["order_id"]
        self.order.update(current_batch=1, status="manufactured", clinician_id=7,
                          assigned_planner={"id": 12}, created_at=datetime.now(),
                          patient_name="Patient", batches=[{"status": "manufactured", "quantity": 4}])
        planner = {"role": "planning", "id": 12, "name": "Planner"}
        clinician = {"role": "clinician", "clinician_id": 7, "clinic_id": 1, "name": "Clinician"}
        issue = main.add_issue(case, main.IssueInput(text="Revise plan", raised_to="planning", batch_number=1),
                               user={"role": "admin", "name": "Admin"})
        self.resolve(issue["issue_id"], "planning", revision=True, id=12)
        main.change_status(case, main.StatusInput(status="plan_completed", batch_number=1), planner)
        with patch.object(self.store, "find", create=True, return_value=[self.order]):
            self.assertEqual(main.clinic_overview(clinician)["approvals"][0]["order_id"], case)
        self.assertTrue(self.order["batches"][0]["revision_approval_required"])
        main.change_status(case, main.StatusInput(status="clinician_approved", batch_number=1), clinician)
        self.assertEqual(self.order["batches"][0]["status"], "clinician_approved")
        self.assertFalse(self.order["batches"][0]["revision_approval_required"])

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
                if self.order["batches"][number - 1]["status"] == "planning_in_progress":
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
                self.assertEqual(self.order["current_batch"], 1)
                self.assertEqual(self.order["batches"][0]["status"], "issue_raised")
                with self.assertRaises(HTTPException):
                    change("plan_completed", batch_number=2)
                self.resolve(self.order["issues"][0]["id"], "production")
                self.assertEqual(self.order["current_batch"], 1)
            change("qc_approved", batch_number=number)
            self.assertEqual(self.order["current_batch"], min(number + 1, 4))
            self.assertEqual(self.order["status"], {4: "qc_approved"}.get(number, "planning_in_progress"))

    def test_qc_issue_routes_to_lab_and_blocks_approval(self):
        self.raise_qc_issue()
        self.raise_qc_issue()
        self.resolve(self.order["issues"][0]["id"], "production")
        self.assertEqual(self.order["status"], "issue_raised")
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
        self.resolve(issue_id, "production")
        self.assertEqual(self.order["status"], "manufactured")
        self.assertIsNotNone(self.order["issues"][0]["resolved_at"])
        main.change_status("ORD-000001", main.StatusInput(status="qc_approved"),
                           user={"role": "planning", "name": "Reviewer"})
        self.assertEqual(self.order["status"], "qc_approved")

    def test_internal_issue_can_target_another_team_until_completion(self):
        main.add_issue("ORD-000001", main.IssueInput(text="Check scan", raised_to="scanner"),
                       user={"role": "planning", "name": "Reviewer"})
        self.resolve(self.order["issues"][0]["id"], "scanner")
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

    def test_clinician_triage_and_mixed_resolution_outcomes(self):
        case = self.order["order_id"]
        self.order.update(clinician_id=7, assigned_planner={"id": 12})
        for role in ("clinician", "clinic_admin"):
            main.add_issue(case, main.IssueInput(text="Check fit", raised_to="production"),
                           {"role": role, "name": role})
        first, second = self.order["issues"]
        self.assertIsNone(first["raised_to"])
        assignment = main.IssueAssignment(raised_to="clinician")
        with self.assertRaises(HTTPException):
            main.assign_issue(case, first["id"], assignment, {"role": "production"})
        main.assign_issue(case, first["id"], assignment, {"role": "marketing", "name": "M"})
        with self.assertRaises(HTTPException):
            self.resolve(first["id"], "clinician", clinician_id=8)
        self.resolve(first["id"], "clinician", revision=True, clinician_id=7)
        self.assertEqual(self.order["status"], "issue_raised")
        main.assign_issue(case, second["id"], main.IssueAssignment(raised_to="marketing"), {"role": "admin", "name": "A"})
        self.resolve(second["id"], "marketing")
        self.assertEqual(self.order["status"], "planning_in_progress")
        main.change_status(case, main.StatusInput(status="plan_completed", aligner_quantity=2),
                           {"role": "planning", "id": 12, "name": "P"})
        approval = main.StatusInput(status="clinician_approved", dispatch_mode="together")
        with self.assertRaises(HTTPException):
            main.change_status(case, approval, {"role": "clinician", "clinician_id": 8, "name": "C"})
        main.change_status(case, approval, {"role": "marketing", "name": "M"})
        self.assertEqual(self.order["status"], "clinician_approved")
        self.assertFalse(self.order["revision_approval_required"])

    def test_legacy_feedback_can_still_be_resolved(self):
        self.order.update(status="clinician_issues", issues=[{"raised_to": "cad", "id": "legacy", "resolved_at": None}])
        main.resolve_issue(self.order["order_id"], "legacy", {"role": "planning", "name": "P"})
        self.assertEqual(self.order["status"], "plan_completed")

    def test_admin_manufactures_and_production_resolves(self):
        admin = {"role": "admin", "name": "Administrator", "id": 1}
        self.order["status"] = "clinician_approved"
        for status in ("manufacturing_in_process", "manufactured"):
            main.change_status("ORD-000001", main.StatusInput(status=status), user=admin)
            self.assertEqual(self.order["status"], status)
        main.add_issue("ORD-000001", main.IssueInput(text="Remake tray", raised_to="production"), admin)
        self.resolve(self.order["issues"][0]["id"], "production")
        self.assertEqual(self.order["status"], "manufactured")
        self.assertEqual(self.order["history"][-1]["by"], "production")
        main.change_status("ORD-000001", main.StatusInput(status="qc_approved"), user=admin)
        self.assertEqual(self.order["status"], "qc_approved")

    def test_production_can_review_and_approve_after_resolution(self):
        maker = {"role": "production", "name": "Maker"}
        with self.assertRaises(HTTPException):
            main.add_issue("ORD-000001", main.IssueInput(text="Remake tray", raised_to="production"), maker)
        main.add_issue("ORD-000001", main.IssueInput(text="Confirm details", raised_to="marketing"), maker)
        approval = main.StatusInput(status="qc_approved")
        with self.assertRaises(HTTPException) as caught:
            main.change_status("ORD-000001", approval, maker)
        self.assertEqual(caught.exception.status_code, 409)
        self.resolve(self.order["issues"][0]["id"], "admin")
        main.change_status("ORD-000001", approval, maker)
        self.assertEqual(self.order["history"][-1]["by"], "Maker")
        self.assertEqual(self.order["status"], "qc_approved")

    def test_admin_can_raise_clinician_issue_and_approve_after_resolution(self):
        admin = {"role": "admin", "name": "Administrator", "id": 1}
        approval = main.StatusInput(status="clinician_approved")
        self.order["status"] = "plan_completed"
        main.add_issue("ORD-000001", main.IssueInput(text="Revise plan", raised_to="planning"), admin)
        self.assertEqual(self.order["status"], "issue_raised")
        issue = self.order["issues"][0]
        self.assertEqual(issue["raised_to"], "planning")
        self.assertEqual(issue["by"], "Administrator")
        with self.assertRaises(HTTPException) as caught:
            main.change_status("ORD-000001", approval, admin)
        self.assertEqual(caught.exception.status_code, 409)
        self.resolve(issue["id"], "planning")
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
