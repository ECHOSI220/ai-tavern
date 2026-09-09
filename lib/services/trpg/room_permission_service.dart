import '../../models/social_models.dart';

enum RoomPermission {
  invite,
  kick,
  start,
  pause,
  changeHost,
  editCampaign,
  manageRoles,
  announce,
  backup,
  restore,
  archive,
  delete,
  transferOwnership,
}

class RoomPermissionService {
  const RoomPermissionService();

  bool can(
    PersistentCampaignRoom room,
    String userId,
    RoomPermission permission,
  ) {
    final member = room.member(userId);
    if (member == null || member.status != MembershipStatus.active) {
      return false;
    }
    if (member.permissions.contains(permission.name)) return true;
    return switch (member.role) {
      CampaignMemberRole.owner => true,
      CampaignMemberRole.admin => !const {
        RoomPermission.delete,
        RoomPermission.transferOwnership,
      }.contains(permission),
      CampaignMemberRole.humanGm => const {
        RoomPermission.start,
        RoomPermission.pause,
        RoomPermission.changeHost,
        RoomPermission.announce,
      }.contains(permission),
      CampaignMemberRole.player =>
        permission == RoomPermission.invite &&
            room.invitePermission == InvitePermission.allMembers,
      CampaignMemberRole.spectator => false,
    };
  }

  void require(
    PersistentCampaignRoom room,
    String userId,
    RoomPermission permission,
  ) {
    if (!can(room, userId, permission)) {
      throw StateError('没有 ${permission.name} 权限');
    }
  }
}
