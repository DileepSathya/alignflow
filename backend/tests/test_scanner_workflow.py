import unittest
import asyncio
import io
import tempfile
from pathlib import Path
from types import SimpleNamespace
from copy import deepcopy
from datetime import timedelta
from unittest.mock import patch, MagicMock
from fastapi import HTTPException
from starlette.datastructures import Headers, UploadFile
from app import main

SCANNER = {'id': 12, 'name': 'Scanner', 'role': 'scanner'}
MARKETING = {'id': 13, 'name': 'Marketing', 'role': 'marketing'}
ADMIN = {'id': 1, 'name': 'Admin', 'role': 'admin'}
PLANNER = {'id': 20, 'name': 'Planner', 'role': 'planning'}

class ScannerTests(unittest.TestCase):
    def setUp(self):
        self.doc = {'_id': 'test', 'order_id': 'ORD-000001', 'status': 'scanner_review',
                    'updated_at': main.now(), 'documents': [], 'history': [],
                    'checklist': main.new_checklist()}
        self.store = MagicMock()
        self.store.find_one.side_effect = lambda *a: deepcopy(self.doc)
        self.store.find_one_and_update.side_effect = self.update
        self.patch = patch.object(main, 'order_store', return_value=self.store)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def update(self, guard, change, **kw):
        for key, value in guard.items():
            actual = self.doc.get(key)
            if key == 'assigned_planner.id':
                actual = (self.doc.get('assigned_planner') or {}).get('id')
            if actual != value:
                return None
        self.doc.update(deepcopy(change.get('$set', {})))
        for key, amount in change.get('$inc', {}).items():
            self.doc[key] = self.doc.get(key, 0) + amount
        for key, value in change.get('$push', {}).items():
            self.doc.setdefault(key, []).append(deepcopy(value))
        return deepcopy(self.doc)

    def assert_status(self, code, fn, *args, **kwargs):
        with self.assertRaises(HTTPException) as caught:
            fn(*args, **kwargs)
        self.assertEqual(caught.exception.status_code, code)

    def test_clinician_can_prepare_and_submit_assigned_case(self):
        user = dict(id=42, role="clinician", name="Doctor", clinic_id=10, clinician_id=4)
        self.doc.update(clinic_id=10, clinician_id=4)
        for item in self.doc["checklist"]:
            docs = []
            for index in range(item["min_files"]):
                key = f"{item['id']}-{index}"
                self.doc["documents"].append({"id": key, "name": key + item["extensions"][0]})
                docs.append(key)
            main.update_checklist(self.doc["order_id"], item["id"],
                main.ChecklistInput(document_ids=docs, text="Instructions" if item["allow_text"] else ""), user=user)
        self.assert_status(403, main.update_checklist, self.doc["order_id"], "upper_arch",
                           main.ChecklistInput(verified=True), user=user)
        result = main.submit_documents(self.doc["order_id"], user=user)
        self.assertEqual(result["order"]["status"], main.DOCUMENT_REVIEW)

    def test_clinician_decisions_follow_order_stage(self):
        user = dict(id=42, role="clinician", name="Doctor", clinic_id=10, clinician_id=4)
        self.doc.update(clinic_id=10, clinician_id=4, status="plan_completed", issues=[])
        order_id = self.doc["order_id"]
        result = main.add_issue(order_id, main.IssueInput(text="Revise plan", raised_to="planning"), user=user)
        self.assertEqual(result["order"]["status"], "issue_raised")
        self.assertIsNone(result["order"]["issues"][0]["raised_to"])
        self.assert_status(409, main.change_status, order_id, main.StatusInput(status="cancelled"), user=user)
        self.doc.update(status="plan_completed", issues=[])
        main.change_status(order_id, main.StatusInput(status="clinician_approved"), user=user)
        self.assert_status(409, main.change_status, order_id, main.StatusInput(status="cancelled"), user=user)

    def test_snapshot_is_independent(self):
        self.doc['checklist'][0]['extensions'].append('.new')
        self.assertNotIn('.new', main.new_checklist()[0]['extensions'])

    def test_missing_files_cannot_be_verified(self):
        self.assert_status(409, main.update_checklist, self.doc['order_id'], 'upper_arch',
                           main.ChecklistInput(verified=True), user=SCANNER)

    def test_activity_combines_legacy_history_and_new_scanner_action(self):
        timestamp = (main.now() - timedelta(days=1)).replace(microsecond=123000)
        self.doc.update(
            created_at=timestamp, created_by=MARKETING, clinic_id=10,
            history=[{"status": "scanner_review", "at": timestamp, "by": MARKETING["name"]},
                     {"status": "scanner_missing", "at": timestamp, "by": SCANNER["name"]}],
            scanner_history=[{"action": "Requested missing items", "by": SCANNER["name"],
                              "at": timestamp.replace(microsecond=123456).isoformat(),
                              "details": {"status": "scanner_missing"}}],
        )
        main.update_checklist(self.doc["order_id"], "upper_arch",
                              main.ChecklistInput(), user=SCANNER)
        entries = main.order_activity_detail(self.doc["order_id"], user=SCANNER)["activity"]
        self.assertEqual([entry["action"] for entry in entries],
                         ["Updated upper_arch", "Requested missing items", "Order created"])
        self.assertEqual(entries[0]["actor"], SCANNER)
        self.assertEqual(entries[0]["at"], self.doc["updated_at"])
        self.assertEqual(entries[1]["details"]["to_status"], "scanner_missing")
        other_clinic = {"role": "clinic_admin", "clinic_id": 11}
        self.assert_status(404, main.order_activity_detail, self.doc["order_id"], user=other_clinic)

    def test_marketing_cannot_verify_or_approve(self):
        self.assert_status(403, main.update_checklist, self.doc['order_id'], 'upper_arch',
                           main.ChecklistInput(verified=True), user=MARKETING)
        self.assert_status(403, main.approve_documents, self.doc['order_id'],
                           main.DocumentDecision(revision=0), user=MARKETING)

    def test_incomplete_order_cannot_be_approved(self):
        self.assert_status(409, main.submit_documents, self.doc['order_id'], user=SCANNER)

    def test_photo_count_and_duplicate_ids(self):
        item = self.doc['checklist'][3]
        self.doc['documents'] = [{'id': str(i), 'name': f'{i}.jpg'} for i in range(5)]
        item['document_ids'] = ['0'] * 5
        self.assertFalse(main.item_ready(item, self.doc))
        item['document_ids'] = [str(i) for i in range(5)]
        self.assertTrue(main.item_ready(item, self.doc))

    def test_wrong_type_and_foreign_files_rejected(self):
        self.doc['documents'] = [{'id': 'a', 'name': 'scan.txt'}]
        for ids in [['a'], ['foreign']]:
            self.assert_status(422, main.update_checklist, self.doc['order_id'], 'upper_arch',
                               main.ChecklistInput(document_ids=ids), user=SCANNER)

    def test_text_requirements_can_be_verified(self):
        result = main.update_checklist(self.doc['order_id'], 'requirements',
            main.ChecklistInput(text='Instructions', verified=True), user=SCANNER)
        self.assertTrue(result['order']['checklist'][-1]['verified'])
        self.assertEqual(result['order']['checklist'][-1]['verified_by'], 'Scanner')

    def test_admin_exception_then_planner_approval(self):
        for item in self.doc['checklist']:
            main.update_checklist(self.doc['order_id'], item['id'],
                main.ChecklistInput(waiver_reason='Approved clinical exception'), user=ADMIN)
        main.submit_documents(self.doc['order_id'], user=SCANNER)
        result = main.approve_documents(self.doc['order_id'],
            main.DocumentDecision(revision=self.doc['review_revision']), user=PLANNER)['order']
        self.assertEqual(result['status'], 'submitted')
        self.assertTrue(result['scanner_approved'])
        self.assertEqual(result['history'][-1]['status'], 'submitted')
        self.assertEqual(main.get_order(self.doc['order_id'], {'role': 'planning'})['status'], 'submitted')

    def test_scanner_cannot_authorize_exception(self):
        self.assert_status(403, main.update_checklist, self.doc['order_id'], 'upper_arch',
                           main.ChecklistInput(waiver_reason='missing'), user=SCANNER)

    def test_issue_attachment_is_linked_and_retry_keeps_one_copy(self):
        self.doc.update(status='manufactured', issues=[])
        order_id = self.doc['order_id']
        issue_id = main.add_issue(order_id, main.IssueInput(
            text='Tray needs revision', raised_to='production'), user=ADMIN)['issue_id']
        self.store.update_one.side_effect = lambda guard, change: SimpleNamespace(
            matched_count=int(self.update(guard, change) is not None))

        def attach(user):
            upload = UploadFile(filename='tray.stl', file=io.BytesIO(b'solid tray'),
                                headers=Headers({'content-type': 'application/octet-stream'}))
            return asyncio.run(main.upload_order_document(order_id, upload, user=user, issue_id=issue_id))

        with tempfile.TemporaryDirectory() as directory, patch.object(main.settings, 'data_dir', Path(directory)):
            self.assert_status(403, attach, dict(ADMIN, id=42))
            attach(ADMIN)
            order = attach(ADMIN)['order']
            self.assertEqual(len(order['documents']), 1)
            self.assertEqual(order['documents'][0]['issue_id'], order['issues'][0]['id'])
            self.assertEqual(order['documents'][0]['category'], 'issue')
            files = [p for p in Path(directory).rglob('*') if p.is_file()]
            self.assertEqual([p.read_bytes() for p in files], [b'solid tray'])

    def test_admin_can_upload_and_select_a_required_file(self):
        order_id = self.doc['order_id']
        self.store.update_one.side_effect = lambda guard, change: SimpleNamespace(
            matched_count=int(self.update(guard, change) is not None))
        upload = UploadFile(filename='upper.stl', file=io.BytesIO(b'solid scan'),
                            headers=Headers({'content-type': 'application/octet-stream'}))
        with tempfile.TemporaryDirectory() as directory, patch.object(main.settings, 'data_dir', Path(directory)):
            order = asyncio.run(main.upload_order_document(order_id, upload, user=ADMIN))['order']
        document = order['documents'][0]
        self.assertEqual(document['role'], 'admin')
        selection = main.ChecklistInput(document_ids=[document['id']])
        result = main.update_checklist(order_id, 'upper_arch', selection, user=ADMIN)['order']
        self.assertEqual(result['checklist'][0]['document_ids'], [document['id']])
        self.assertEqual(result['documents'][0]['category'], 'scan')
        self.assert_status(403, main.update_checklist, order_id, 'upper_arch',
                           main.ChecklistInput(verified=True), user=ADMIN)
        self.assert_status(409, main.submit_documents, order_id, user=ADMIN)

    def test_uploaded_plan_cannot_be_used_in_scan_checklist(self):
        order_id = self.doc['order_id']
        self.store.update_one.side_effect = lambda guard, change: SimpleNamespace(
            matched_count=int(self.update(guard, change) is not None))
        upload = UploadFile(filename='plan.stl', file=io.BytesIO(b'solid plan'),
                            headers=Headers({'content-type': 'application/octet-stream'}))
        with tempfile.TemporaryDirectory() as directory, patch.object(main.settings, 'data_dir', Path(directory)):
            result = asyncio.run(main.upload_order_document(order_id, upload, user=ADMIN, category='plan'))
        document = result['order']['documents'][0]
        self.assertEqual(document['category'], 'plan')
        self.assert_status(422, main.update_checklist, order_id, 'upper_arch',
                           main.ChecklistInput(document_ids=[document['id']]), user=ADMIN)

    def test_admin_can_classify_an_unlinked_legacy_document(self):
        order_id = self.doc['order_id']
        self.doc['documents'] = [{'id': 'legacy', 'name': 'legacy.pdf'},
                                 {'id': 'scan', 'name': 'scan.stl'}]
        self.doc['scanner_history'] = [{'details': {'checklist': [{'document_ids': ['scan']}]}}]
        body = main.DocumentCategoryInput(category='plan')
        self.assert_status(403, main.classify_order_document, order_id, 'legacy', body, user=SCANNER)
        self.assert_status(409, main.classify_order_document, order_id, 'scan', body, user=ADMIN)

        def classify(guard, update):
            self.assertEqual(guard['documents.id'], 'legacy')
            self.doc['documents'][0]['category'] = update['$set']['documents.$.category']
            return SimpleNamespace(matched_count=1)

        self.store.update_one.side_effect = classify
        result = main.classify_order_document(order_id, 'legacy', body, user=ADMIN)
        self.assertEqual([file['category'] for file in result['order']['documents']], ['plan', 'scan'])

    def test_admin_can_submit_and_approve_complete_documents(self):
        order_id = self.doc['order_id']
        for item in self.doc['checklist']:
            document_ids = []
            for index in range(item['min_files']):
                key = f"{item['id']}-{index}"
                self.doc['documents'].append({'id': key, 'name': key + item['extensions'][0]})
                document_ids.append(key)
            item['document_ids'] = document_ids
        review = main.submit_documents(order_id, user=ADMIN)['order']
        self.assertEqual(review['status'], main.DOCUMENT_REVIEW)
        approved = main.approve_documents(order_id,
            main.DocumentDecision(revision=review['review_revision']), user=ADMIN)['order']
        self.assertEqual(approved['status'], 'submitted')
        self.assertTrue(approved['scanner_approved'])
        self.assertEqual(approved['planner_document_approval']['user_id'], ADMIN['id'])

    def test_admin_can_claim_order_dropped_by_planner(self):
        self.doc.update(status='submitted', scanner_approved=True)
        order_id = self.doc['order_id']
        main.assign_order(order_id, user=PLANNER)
        dropped = main.change_assignment(order_id, main.AssignmentChange(reason='Unavailable'), user=PLANNER)['order']
        self.assertEqual(dropped['status'], 'submitted')
        self.assertIsNone(dropped['assigned_planner'])
        claimed = main.admin_assign_order(order_id, main.AdminAssignment(user_id=ADMIN['id']), admin=ADMIN)['order']
        self.assertEqual(claimed['status'], 'planning_in_progress')
        self.assertEqual(claimed['assigned_planner']['id'], ADMIN['id'])

    def test_admin_reassignment_closes_at_clinician_approval(self):
        self.doc['assigned_planner'] = PLANNER
        for status in main.VISIBLE_PRODUCTION_STEPS:
            with self.subTest(status=status):
                self.doc['status'] = status
                self.assertFalse(main.public_order(self.doc)['planner_assignment_open'])
                self.assert_status(409, main.change_assignment, self.doc['order_id'],
                                   main.AssignmentChange(user_id=ADMIN['id']), user=ADMIN)

    def test_missing_request_visible_to_marketing(self):
        main.request_missing(self.doc['order_id'], main.MissingItemsInput(note='Please upload scans'), user=SCANNER)
        result = main.get_order(self.doc['order_id'], MARKETING)
        self.assertEqual(result['status'], 'scanner_missing')
        self.assertEqual(len(result['missing_request']['items']), 7)

    def test_planning_cannot_access_pending_or_cancelled_unapproved_order(self):
        for status in ['scanner_review', 'scanner_missing', 'cancelled']:
            self.doc['status'] = status
            self.assert_status(404, main.get_order, self.doc['order_id'], {'role': 'planning'})

    def test_planning_filters_cannot_bypass_gate(self):
        self.store.count_documents.return_value = 0
        self.store.find.return_value.sort.return_value.skip.return_value.limit.return_value = []
        main.list_orders(status_filter='scanner_review', user={'role': 'planning'})
        query = self.store.count_documents.call_args.args[0]
        self.assertIn(main.planning_visibility(), query['$and'])

    def test_claim_requires_approval(self):
        self.assert_status(409, main.assign_order, self.doc['order_id'], {'role': 'planning', 'id': 20, 'name': 'Planner'})
        self.assertTrue(self.store.find_one_and_update.call_args.args[0]['scanner_approved'])

    def test_approved_checklist_is_locked(self):
        self.doc['status'] = 'submitted'
        self.doc['scanner_approved'] = True
        self.assert_status(409, main.update_checklist, self.doc['order_id'], 'upper_arch',
                           main.ChecklistInput(), user=SCANNER)

    def test_linked_document_cannot_be_deleted(self):
        self.doc['documents'] = [{'id': 'a', 'name': 'upper.stl', 'role': 'scanner', 'checklist_id': 'upper_arch'}]
        self.assert_status(409, main.delete_order_document, self.doc['order_id'], 'a', user=SCANNER)

    def test_concurrent_edit_rejected(self):
        self.store.find_one_and_update.side_effect = None
        self.store.find_one_and_update.return_value = None
        self.assert_status(409, main.update_checklist, self.doc['order_id'], 'requirements',
                           main.ChecklistInput(text='Instructions'), user=MARKETING)

    def test_revision_blocks_stale_edit_even_with_same_timestamp(self):
        stale = deepcopy(self.doc)
        self.doc['review_revision'] = 1
        self.assert_status(409, main.save_scanner_change, stale,
                           {'checklist': stale['checklist']}, SCANNER, 'stale review')

    def test_upload_links_file_and_invalidates_previous_verification(self):
        item = self.doc['checklist'][0]
        item['verified'] = True
        item['waiver'] = {'reason': 'Old exception'}
        def upload_update(guard, change):
            return SimpleNamespace(matched_count=1 if self.update(guard, change) else 0)
        self.store.update_one.side_effect = upload_update
        upload = UploadFile(filename='upper.stl', file=io.BytesIO(b'solid scan'),
                            headers=Headers({'content-type': 'application/octet-stream'}))
        with tempfile.TemporaryDirectory() as directory, patch.object(main.settings, 'data_dir', Path(directory)):
            result = asyncio.run(main.upload_order_document(self.doc['order_id'], upload,
                user=SCANNER, checklist_id='upper_arch'))['order']
            self.assertEqual(len(result['documents']), 1)
            item = result['checklist'][0]
            self.assertEqual(item['document_ids'], [result['documents'][0]['id']])
            self.assertFalse(item['verified'])
            self.assertIsNone(item['waiver'])
            self.assertTrue(list(Path(directory).rglob('*')))

    def test_complete_review_releases_order(self):
        for item in self.doc['checklist']:
            ids = []
            for index in range(item['min_files']):
                key = f"{item['id']}-{index}"
                self.doc['documents'].append({'id': key, 'name': key + item['extensions'][0]})
                ids.append(key)
            main.update_checklist(self.doc['order_id'], item['id'],
                                  main.ChecklistInput(document_ids=ids, verified=True), user=SCANNER)
        order_id = self.doc['order_id']
        self.doc['clinic_id'] = 14
        self.doc['clinician_id'] = 5
        clinician = {'id': 4, 'name': 'Doctor', 'role': 'clinic_admin', 'clinic_id': 14, 'clinician_id': 5}
        first = main.submit_documents(order_id, user=MARKETING)['order']
        self.assertEqual(main.get_order(order_id, PLANNER)['status'], main.DOCUMENT_REVIEW)
        issue = main.DocumentIssues(revision=first['review_revision'], item_ids=['requirements'],
                                    note='Please clarify the requirements')
        main.raise_document_issues(order_id, issue, user=PLANNER)
        self.assert_status(409, main.submit_documents, order_id, user=clinician)
        edit = main.ChecklistInput(text='Updated instructions')
        self.assert_status(403, main.update_checklist, order_id, 'requirements', edit,
                           user={**clinician, 'clinician_id': 8})
        self.assert_status(404, main.update_checklist, order_id, 'requirements', edit,
                           user={**clinician, 'clinic_id': 99})
        main.update_checklist(order_id, 'requirements', edit, user=clinician)
        second = main.submit_documents(order_id, user=clinician)['order']
        self.assert_status(409, main.approve_documents, order_id, issue, user=PLANNER)
        result = main.approve_documents(order_id,
            main.DocumentDecision(revision=second['review_revision']), user=PLANNER)['order']
        self.assertEqual(result['status'], 'submitted')
        self.assertEqual(result['planner_document_approval']['user_id'], PLANNER['id'])

    def test_legacy_migration_targets_only_unassigned_unapproved_submissions(self):
        collection = MagicMock()
        with patch.object(main, '_orders_indexed', False), patch.object(main, 'orders', collection):
            # Bypass this test fixture's order_store patch.
            self.patch.stop()
            try:
                main.order_store()
                main.order_store()
            finally:
                self.patch.start()
        collection.update_many.assert_called_once()
        query, update = collection.update_many.call_args.args
        self.assertEqual(query, {'status': 'submitted', 'assigned_planner': None,
                                 'scanner_approved': {'$ne': True}})
        self.assertEqual(update['$set']['status'], 'scanner_review')

if __name__ == '__main__':
    unittest.main()
