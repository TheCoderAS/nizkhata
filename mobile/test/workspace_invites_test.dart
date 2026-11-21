import 'package:flutter_test/flutter_test.dart';
import 'package:nizkhata/data/workspace_invites.dart';

void main() {
  final now = DateTime(2026, 11, 21);
  ({String id, Map<String, dynamic> data}) inv(String id, Map<String, dynamic> m) => (
        id: id,
        data: {'workspaceId': 'w1', 'email': 'a@x.com', 'roleId': 'r1', 'status': 'pending', ...m},
      );

  test('offers pending, unexpired invites to workspaces not yet joined', () {
    final list = pendingInvites([
      inv('ok', {'workspaceName': 'Home', 'invitedByName': 'Asha', 'roleName': 'Editor'}),
      inv('expired', {'workspaceId': 'w2', 'expiresAt': DateTime(2026, 11, 1)}),
      inv('answered', {'workspaceId': 'w3', 'status': 'accepted'}),
      inv('joined', {'workspaceId': 'w4'}),
      inv('broken', {'workspaceId': '', 'roleId': ''}),
    ], memberOf: {'w4'}, now: now);
    expect(list.map((i) => i.id), ['ok']);
    expect(list.single.title, 'Home');
    expect(list.single.invitedByName, 'Asha');
    expect(list.single.roleName, 'Editor');
  });

  test('an invite made before names were stored still shows', () {
    final list = pendingInvites([inv('old', {})], memberOf: const {}, now: now);
    expect(list.single.title, 'A workspace');
    expect(list.single.workspaceName, isNull);
  });
}
