-- Phase 1 예보 엔진 테이블. Edge Function(서비스 키)만 접근하므로 RLS를 켜고 정책은 두지 않는다.

-- 집·회사·여행지. 좌표는 소수 2자리(약 1km)로만 저장한다.
create table public.places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade, -- Phase 2 앱 사용자 연결용
  kind text not null check (kind in ('home', 'office', 'trip')),
  name text not null,
  lat numeric(5, 2) not null check (lat between -90 and 90),
  lon numeric(5, 2) not null check (lon between -180 and 180),
  tz text not null default 'Asia/Seoul',
  kma_nx integer, -- 기상청 격자 (refresh가 자동 계산)
  kma_ny integer,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 소스별·위치별 최신 예보 (위치 키: 기상청 'kma:nx:ny', 그 외 'll:lat:lon')
create table public.forecast_cache (
  provider text not null,
  loc_key text not null,
  issued_at timestamptz not null,
  fetched_at timestamptz not null,
  expires_at timestamptz not null,
  payload jsonb not null,
  primary key (provider, loc_key)
);

-- 정확도 분석용 예보 기록 (발표 주기마다 1회, 향후 72시간 강수확률)
create table public.forecast_log (
  id bigint generated always as identity primary key,
  provider text not null,
  loc_key text not null,
  issued_at timestamptz not null,
  fetched_at timestamptz not null default now(),
  slots jsonb not null,
  unique (provider, loc_key, issued_at)
);

-- 기상청 초단기실황 (관측). rn1 = 직전 1시간 강수량(mm)
create table public.obs_log (
  loc_key text not null,
  obs_time timestamptz not null,
  rn1 numeric,
  pty smallint,
  t1h numeric,
  fetched_at timestamptz not null default now(),
  primary key (loc_key, obs_time)
);

alter table public.places enable row level security;
alter table public.forecast_cache enable row level security;
alter table public.forecast_log enable row level security;
alter table public.obs_log enable row level security;
