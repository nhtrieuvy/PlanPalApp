enum PlanStatus { upcoming, ongoing, completed, cancelled, unknown }

PlanStatus parsePlanStatus(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'upcoming':
    case 'iscoming': // legacy alias
      return PlanStatus.upcoming;
    case 'ongoing':
      return PlanStatus.ongoing;
    case 'completed':
    case 'done':
      return PlanStatus.completed;
    case 'cancelled':
    case 'canceled':
      return PlanStatus.cancelled;
    default:
      return PlanStatus.unknown;
  }
}

String planStatusLabel(PlanStatus s) {
  switch (s) {
    case PlanStatus.upcoming:
      return 'Sắp diễn ra';
    case PlanStatus.ongoing:
      return 'Đang diễn ra';
    case PlanStatus.completed:
      return 'Hoàn thành';
    case PlanStatus.cancelled:
      return 'Huỷ';
    case PlanStatus.unknown:
      return 'Không rõ';
  }
}
