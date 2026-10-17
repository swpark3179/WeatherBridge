import type { CommuteAttributes, CommuteState } from "./apns.ts";

/** 스파이크용 샘플 브리핑 (실제 예보 아님). windowMinutes 뒤가 출근 시각 T. */
export function sampleCommute(nowSec: number, windowMinutes: number): {
  attributes: CommuteAttributes;
  state: CommuteState;
} {
  const kstHour = new Date((nowSec + 9 * 3600) * 1000).getUTCHours();
  return {
    attributes: { windowEnd: nowSec + windowMinutes * 60, firstHour: kstHour },
    state: {
      headline: "☔ 회사 15–18시 최대 70% (샘플)",
      highlight: true,
      places: [
        {
          name: "집",
          temp: 12,
          pops: [0, 0, 10, 10, 10, 10, 20, 20, 20, 10, 10, 10],
          maxPop: 20,
          rainWindow: null,
        },
        {
          name: "회사",
          temp: 15,
          pops: [0, 0, 10, 10, 20, 30, 40, 50, 60, 70, 60, 40],
          maxPop: 70,
          rainWindow: "15–18시",
        },
      ],
      updatedAt: nowSec,
    },
  };
}
