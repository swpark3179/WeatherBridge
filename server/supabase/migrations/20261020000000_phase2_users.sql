-- Phase 2: 앱 사용자(익명 로그인)별 장소·설정·기기·발송 기록.
-- - 앱은 publishable key + 사용자 JWT로 접근하고, RLS로 본인 행만 읽는다. 쓰기는 아래 RPC로만 한다(user_settings 제외).
-- - Edge Function은 비밀 키(service_role)로 접근한다.
-- - 2026-10-30부터 public 테이블이 Data API에 자동으로 노출되지 않으므로 권한을 모두 명시한다.

-- ---------- 장소: 사용자별 활성 집·회사 1곳씩 ----------
create unique index places_user_home_office on public.places (user_id, kind)
  where active and user_id is not null and kind in ('home', 'office');

create policy "places: 본인 행 읽기" on public.places
  for select to authenticated using (user_id = (select auth.uid()));

-- ---------- 사용자 설정 (1인 1행) ----------
create table public.user_settings (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  tz text not null default 'Asia/Seoul',
  summary_enabled boolean not null default false,
  -- 현지 시각
  summary_time time not null default '07:00',
  commute_time time not null default '08:30',
  -- ISO 요일 1=월 … 7=일 (Phase 3 출근 브리핑)
  commute_days smallint[] not null default '{1,2,3,4,5}',
  skip_holidays boolean not null default true,
  threshold smallint not null default 30 check (threshold between 10 and 90),
  updated_at timestamptz not null default now(),
  check (commute_days <@ '{1,2,3,4,5,6,7}'::smallint[])
);
alter table public.user_settings enable row level security;

create policy "user_settings: 본인 행 읽기" on public.user_settings
  for select to authenticated using (user_id = (select auth.uid()));
create policy "user_settings: 본인 행 추가" on public.user_settings
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "user_settings: 본인 행 수정" on public.user_settings
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------- 기기 (APNs 토큰) ----------
create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  apns_token text not null unique,
  -- 앱 빌드 구성에서 정한다: TestFlight/App Store = production, Xcode 디버그 = sandbox
  apns_env text not null check (apns_env in ('sandbox', 'production')),
  -- Phase 3 Live Activity 원격 시작
  push_to_start_token text,
  app_version text,
  active boolean not null default true,
  deactivated_reason text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index devices_active_user on public.devices (user_id) where active;
alter table public.devices enable row level security;

create policy "devices: 본인 행 읽기" on public.devices
  for select to authenticated using (user_id = (select auth.uid()));

-- ---------- 발송 기록 (하루 한 번 보장) ----------
create table public.dispatch_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('summary')),
  local_date date not null,
  scheduled_at timestamptz not null,
  -- pending: 발송 중, retry: 다음 실행에서 다시 시도, sent/failed/skipped: 끝
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'retry', 'failed', 'skipped')),
  attempts smallint not null default 1,
  detail jsonb,
  updated_at timestamptz not null default now(),
  unique (user_id, kind, local_date)
);
alter table public.dispatch_log enable row level security;

create policy "dispatch_log: 본인 행 읽기" on public.dispatch_log
  for select to authenticated using (user_id = (select auth.uid()));

-- ---------- APNs 공급자 토큰 공유 캐시 ----------
-- 함수 인스턴스마다 새로 만들면 20분 제한(TooManyProviderTokenUpdates)에 걸리므로 DB에 두고 50분간 재사용한다.
create table public.apns_provider_token (
  key_id text primary key,
  token text not null,
  issued_at timestamptz not null
);
alter table public.apns_provider_token enable row level security;

-- ---------- 권한 ----------
revoke all on public.places, public.user_settings, public.devices, public.dispatch_log,
  public.apns_provider_token from anon, authenticated;
grant select on public.places, public.devices, public.dispatch_log to authenticated;
grant select, insert, update on public.user_settings to authenticated;
grant select, insert, update, delete on public.places, public.user_settings, public.devices,
  public.dispatch_log, public.apns_provider_token to service_role;
grant usage, select on sequence public.dispatch_log_id_seq to service_role;

-- ---------- RPC (앱 전용 쓰기 경로) ----------

-- 집·회사 저장. 좌표는 소수 둘째 자리(약 1km)로 반올림해 저장하고, 이전 장소는 지운다.
create function public.set_place(
  p_kind text,
  p_name text,
  p_lat double precision,
  p_lon double precision,
  p_tz text default 'Asia/Seoul'
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  new_id uuid;
begin
  if uid is null then
    raise exception '로그인이 필요합니다' using errcode = '42501';
  end if;
  if p_kind not in ('home', 'office') then
    raise exception 'kind는 home 또는 office여야 합니다' using errcode = '22023';
  end if;
  if coalesce(length(btrim(p_name)), 0) not between 1 and 30 then
    raise exception '이름은 1~30자여야 합니다' using errcode = '22023';
  end if;

  delete from public.places where user_id = uid and kind = p_kind;
  insert into public.places (user_id, kind, name, lat, lon, tz)
  values (uid, p_kind, btrim(p_name), round(p_lat::numeric, 2), round(p_lon::numeric, 2),
    coalesce(nullif(btrim(p_tz), ''), 'Asia/Seoul'))
  returning id into new_id;
  return new_id;
end;
$$;

-- 기기 등록. 같은 토큰이 다른 사용자에게 있으면(앱 재설치) 지금 사용자로 옮긴다.
create function public.register_device(
  p_token text,
  p_env text,
  p_push_to_start_token text default null,
  p_app_version text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception '로그인이 필요합니다' using errcode = '42501';
  end if;
  if p_env not in ('sandbox', 'production') then
    raise exception 'env는 sandbox 또는 production이어야 합니다' using errcode = '22023';
  end if;
  if p_token !~ '^[0-9a-f]{32,400}$' then
    raise exception 'APNs 토큰 형식이 아닙니다' using errcode = '22023';
  end if;

  insert into public.devices as d
    (user_id, apns_token, apns_env, push_to_start_token, app_version, active, deactivated_reason,
     last_seen_at)
  values (uid, p_token, p_env, p_push_to_start_token, left(p_app_version, 40), true, null, now())
  on conflict (apns_token) do update set
    user_id = excluded.user_id,
    apns_env = excluded.apns_env,
    push_to_start_token = coalesce(excluded.push_to_start_token, d.push_to_start_token),
    app_version = excluded.app_version,
    active = true,
    deactivated_reason = null,
    last_seen_at = now();
end;
$$;

-- 계정 삭제. 장소·설정·기기·발송 기록도 함께 지워진다(on delete cascade).
create function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.set_place(text, text, double precision, double precision, text),
  public.register_device(text, text, text, text), public.delete_my_account()
  from public, anon;
grant execute on function public.set_place(text, text, double precision, double precision, text),
  public.register_device(text, text, text, text), public.delete_my_account()
  to authenticated;
