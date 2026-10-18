/**
 * 위경도 → 기상청 동네예보 격자(nx, ny). 기상청 Lambert 정각원추도법(5km 격자) 공식.
 * 기준값: 서울시청(37.5665, 126.9780) → (60, 127)
 */
const RE = 6371.00877; // 지구 반경(km)
const GRID = 5.0; // 격자 간격(km)
const SLAT1 = 30.0; // 표준위도 1
const SLAT2 = 60.0; // 표준위도 2
const OLON = 126.0; // 기준점 경도
const OLAT = 38.0; // 기준점 위도
const XO = 43; // 기준점 X 격자
const YO = 136; // 기준점 Y 격자

const DEGRAD = Math.PI / 180;
const re = RE / GRID;
const slat1 = SLAT1 * DEGRAD;
const slat2 = SLAT2 * DEGRAD;
const olon = OLON * DEGRAD;
const olat = OLAT * DEGRAD;
const sn = Math.log(Math.cos(slat1) / Math.cos(slat2)) /
  Math.log(Math.tan(Math.PI * 0.25 + slat2 * 0.5) / Math.tan(Math.PI * 0.25 + slat1 * 0.5));
const sf = Math.pow(Math.tan(Math.PI * 0.25 + slat1 * 0.5), sn) * Math.cos(slat1) / sn;
const ro = re * sf / Math.pow(Math.tan(Math.PI * 0.25 + olat * 0.5), sn);

export interface KmaGrid {
  nx: number;
  ny: number;
}

export function toKmaGrid(lat: number, lon: number): KmaGrid {
  const ra = re * sf / Math.pow(Math.tan(Math.PI * 0.25 + lat * DEGRAD * 0.5), sn);
  let theta = lon * DEGRAD - olon;
  if (theta > Math.PI) theta -= 2 * Math.PI;
  if (theta < -Math.PI) theta += 2 * Math.PI;
  theta *= sn;
  return {
    nx: Math.floor(ra * Math.sin(theta) + XO + 0.5),
    ny: Math.floor(ro - ra * Math.cos(theta) + YO + 0.5),
  };
}

/** 기상청 단기예보가 제공되는 범위(한반도 주변)인지. 해외 지점은 기상청 소스를 쓰지 않는다. */
export function isKmaCovered(lat: number, lon: number): boolean {
  return lat >= 32.5 && lat <= 39.0 && lon >= 124.0 && lon <= 132.0;
}

export function kmaLocKey(grid: KmaGrid): string {
  return `kma:${grid.nx}:${grid.ny}`;
}
