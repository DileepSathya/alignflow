import unittest

from app import main


class _Cursor:
    def __init__(self):
        self.rows = []
        self.inserted_id = 10
        self.kept_ids = None

    def execute(self, query, params):
        if query.startswith("SELECT clinician_id"):
            self.rows = [{"clinician_id": value} for value in params[1]]
        elif query.startswith("INSERT INTO clinicians"):
            self.rows = [{"clinician_id": self.inserted_id}]
            self.inserted_id += 1
        elif query.startswith("DELETE FROM clinicians"):
            self.kept_ids = params[1]

    def fetchone(self):
        return self.rows[0]

    def fetchall(self):
        return self.rows


class ClinicianSaveTests(unittest.TestCase):
    def test_new_clinicians_are_kept_after_insert(self):
        cursor = _Cursor()
        people = [
            main.ClinicianInput(name="A", mobile_number="111"),
            main.ClinicianInput(name="B", mobile_number="222"),
        ]

        main.save_clinicians(cursor, 3, people)

        self.assertEqual(cursor.kept_ids, [10, 11])

    def test_existing_and_new_clinicians_are_kept(self):
        cursor = _Cursor()
        people = [
            main.ClinicianInput(clinician_id=4, name="A", mobile_number="111"),
            main.ClinicianInput(name="B", mobile_number="222"),
        ]

        main.save_clinicians(cursor, 3, people)

        self.assertEqual(cursor.kept_ids, [4, 10])


if __name__ == "__main__":
    unittest.main()
