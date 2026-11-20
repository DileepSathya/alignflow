import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from fastapi import HTTPException
from app import main


class Orders:
    def __init__(self, rows):
        self.rows = rows
        self.query = None
    def find(self, query, projection=None):
        self.query = query
        return [r for r in self.rows if r['clinic_id'] == query['clinic_id']]


class ClinicOverviewTests(unittest.TestCase):
    def test_scope_counts_and_revision_age(self):
        at = datetime(2026, 1, 1, tzinfo=timezone.utc)
        rows = [dict(order_id=str(i), clinic_id=clinic, clinician_id=1,
                     patient_name='Patient', created_at=at, updated_at=at,
                     status=status, history=[{'status': 'clinician_issues', 'at': at},
                                             {'status': status, 'at': at}])
                for i, (clinic, status) in enumerate([(1, 'plan_completed'),
                    (1, 'qc_approved'), (1, 'manufacture_completed'),
                    (1, 'cancelled'), (1, 'scanner_missing'), (2, 'plan_completed')])]
        store = Orders(rows)
        with patch.object(main, 'order_store', return_value=store), patch.object(main, 'now', return_value=at):
            result = main.clinic_overview(user={'role': 'clinic_admin', 'clinic_id': 1})
        self.assertEqual(store.query, {'clinic_id': 1})
        self.assertEqual(result['counts']['total'], 5)
        self.assertEqual(result['counts']['active'], 2)
        self.assertEqual(result['counts']['completed'], 2)
        self.assertEqual(result['months'][0], 5)
        self.assertEqual(len(result['approvals']), 1)
        self.assertTrue(result['approvals'][0]['revised'])
        self.assertEqual(result['approvals'][0]['stage_since'], at.isoformat())
        self.assertEqual(result['clinicians']['1']['approval'], 1)

    def test_other_roles_rejected(self):
        with self.assertRaises(HTTPException) as error:
            main.clinic_overview(user={'role': 'marketing'})
        self.assertEqual(error.exception.status_code, 403)

    def test_empty_clinic(self):
        with patch.object(main, 'order_store', return_value=Orders([])):
            result = main.clinic_overview(user={'role': 'clinic_admin', 'clinic_id': 1})
        self.assertEqual(result['counts']['total'], 0)
        self.assertEqual(result['recent'], [])

    def test_drilldown_filters_keep_clinic_scope(self):
        from tests.test_cad_overview import _Orders
        store = _Orders()
        with patch.object(main, 'order_store', return_value=store):
            main.list_orders(status_group='active', clinician_id=7, created_month='2026-12',
                             user={'role': 'clinic_admin', 'clinic_id': 4})
        self.assertEqual(store.last_query['clinic_id'], 4)
        self.assertEqual(store.last_query['clinician_id'], 7)
        self.assertNotIn('cancelled', store.last_query['status']['$in'])
        self.assertNotIn('qc_approved', store.last_query['status']['$in'])
        self.assertEqual(store.last_query['created_at']['$lt'].year, 2027)
