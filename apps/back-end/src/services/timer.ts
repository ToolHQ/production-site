/**
 * Computes elapsedTime string
 */
export const computeElapsedTimeMsFromHrTimes = (
  hrTimeEnd: [number, number],
  hrTimeStart: [number, number]
): number =>
  (hrTimeEnd[0] - hrTimeStart[0]) * 1e3 +
  (hrTimeEnd[1] - hrTimeStart[1]) * 1e-6;
