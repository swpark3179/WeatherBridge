-- Phase 5A: 여행. 목적지는 places(kind='trip') 한 행이고, 기간은 trips에 둔다.
-- - 기간은 목적지 현지 달력 날짜(date)다. 앱은 trips 함수로 읽고, 쓰기는 아래 RPC로만 한다.
-- - refresh는 끝나지 않았고 16일 안에 시작하는 여행의 목적지만 받는다(forecast_service.ts isTripWatched).
-- - 2026-10-30부터 public 테이블이 Data API에 자동으로 노출되지 않으므로 권한을 모두 명시한다.

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  place_id uuid not null unique references public.places (id) on delete cascade,
  start_date date not null,
  end_date date not null,
  created_at timestamptz not null default now(),
  check (end_date >= start_date and end_date - start_date <= 30)
);
create index trips_user on public.trips (user_id);
alter table public.trips enable row level security;

create policy "trips: 본인 행 읽기" on public.trips
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.trips from anon, authenticated;
grant select on public.trips to authenticated;
grant select, insert, update, delete on public.trips to service_role;

-- 여행 저장. p_id가 없으면 새로 만들고, 있으면 본인 여행의 목적지·기간을 바꾼다.
-- 좌표는 소수 둘째 자리(약 1km)로 반올림하고, 바뀐 좌표로 기상청 격자를 다시 계산하도록 비운다.
create function public.set_trip(
  p_name text,
  p_lat double precision,
  p_lon double precision,
  p_tz text,
  p_start date,
  p_end date,
  p_id uuid default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_place uuid;
  v_trip uuid;
begin
  if uid is null then
    raise exception '로그인이 필요합니다' using errcode = '42501';
  end if;
  if coalesce(length(btrim(p_name)), 0) not between 1 and 30 then
    raise exception '이름은 1~30자여야 합니다' using errcode = '22023';
  end if;
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180
  then
    raise exception '좌표가 올바르지 않습니다' using errcode = '22023';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) then
    raise exception '알 수 없는 시간대입니다: %', p_tz using errcode = '22023';
  end if;
  if p_start is null or p_end is null or p_end < p_start then
    raise exception '여행 기간이 올바르지 않습니다' using errcode = '22023';
  end if;
  if p_end - p_start > 30 then
    raise exception '여행 기간은 31일까지입니다' using errcode = '22023';
  end if;
  if p_end < current_date - 1 or p_start > current_date + 365 then
    raise exception '여행 날짜는 오늘부터 1년 안이어야 합니다' using errcode = '22023';
  end if;
  if (select count(*) from public.trips
      where user_id = uid and end_date >= current_date - 1 and id is distinct from p_id) >= 10 then
    raise exception '여행은 10개까지 등록할 수 있습니다' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.places (user_id, kind, name, lat, lon, tz)
    values (uid, 'trip', btrim(p_name), round(p_lat::numeric, 2), round(p_lon::numeric, 2), p_tz)
    returning id into v_place;
    insert into public.trips (user_id, place_id, start_date, end_date)
    values (uid, v_place, p_start, p_end)
    returning id into v_trip;
    return v_trip;
  end if;

  select place_id into v_place from public.trips where id = p_id and user_id = uid;
  if v_place is null then
    raise exception '여행을 찾을 수 없습니다' using errcode = '22023';
  end if;
  update public.places set
    name = btrim(p_name),
    lat = round(p_lat::numeric, 2),
    lon = round(p_lon::numeric, 2),
    tz = p_tz,
    kma_nx = null,
    kma_ny = null,
    active = true
  where id = v_place;
  update public.trips set start_date = p_start, end_date = p_end where id = p_id;
  return p_id;
end;
$$;

-- 여행 삭제. 목적지 장소를 지우면 여행도 지워진다(on delete cascade). 없는 여행이면 아무것도 하지 않는다.
create function public.delete_trip(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception '로그인이 필요합니다' using errcode = '42501';
  end if;
  delete from public.places
  where id = (select place_id from public.trips where id = p_id and user_id = uid);
end;
$$;

revoke execute on function
  public.set_trip(text, double precision, double precision, text, date, date, uuid),
  public.delete_trip(uuid)
  from public, anon;
grant execute on function
  public.set_trip(text, double precision, double precision, text, date, date, uuid),
  public.delete_trip(uuid)
  to authenticated;
