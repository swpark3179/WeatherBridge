-- register_device의 토큰 형식 검사 수정.
-- PostgreSQL 정규식은 반복 횟수 상한이 255라 '{32,400}'이 "invalid repetition count(s)"(2201B)를 내서
-- 앱의 기기 등록이 모두 실패했다. 길이는 length()로 따로 본다.
-- create or replace는 소유자와 권한(grant/revoke)을 그대로 둔다.
create or replace function public.register_device(
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
  if length(p_token) not between 32 and 400 or p_token !~ '^[0-9a-f]+$' then
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
