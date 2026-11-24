import 'package:alignflow/orders_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows only the clinician assigned to the order', () {
    final order = {
      'clinician_id': 2,
      'clinic': {
        'clinicians': [
          {'clinician_id': 1, 'name': 'First clinician'},
          {'clinician_id': 2, 'name': 'Assigned clinician'},
        ],
      },
    };

    expect(assignedClinicianName(order), 'Assigned clinician');
    expect(assignedClinicianName({...order, 'clinician_id': 3}), '—');
    expect(assignedClinicianName({'clinic': order['clinic']}), '—');
  });
}
