/** 스파이크용 함수 보호: `x-spike-token` 헤더가 SPIKE_TOKEN 시크릿과 같아야 한다. */
export function checkSpikeToken(req: Request, expected: string | undefined): Response | null {
  if (!expected) {
    return json({ error: "SPIKE_TOKEN 시크릿이 설정되지 않았습니다." }, 503);
  }
  const given = req.headers.get("x-spike-token") ?? "";
  if (!constantTimeEqual(given, expected)) {
    return json({ error: "unauthorized" }, 401);
  }
  return null;
}

function constantTimeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
