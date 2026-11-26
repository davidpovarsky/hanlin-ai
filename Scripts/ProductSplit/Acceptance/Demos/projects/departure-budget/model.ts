export interface DeparturePlan {
  startPreparing: Date;
  leaveHome: Date;
  expectedArrival: Date;
  totalMinutes: number;
}

export function planDeparture(
  targetArrival: Date,
  travelMinutes: number,
  preparationMinutes: number,
  bufferMinutes: number,
): DeparturePlan {
  const expectedArrival = new Date(targetArrival.getTime() - bufferMinutes * 60_000);
  const leaveHome = new Date(expectedArrival.getTime() - travelMinutes * 60_000);
  const startPreparing = new Date(leaveHome.getTime() - preparationMinutes * 60_000);
  return {
    startPreparing,
    leaveHome,
    expectedArrival,
    totalMinutes: travelMinutes + preparationMinutes + bufferMinutes,
  };
}

export function nextArrival(): Date {
  const next = new Date();
  next.setHours(next.getHours() + 2, 0, 0, 0);
  return next;
}
