-- 주기 실행(pg_cron)과 DB → Edge Function 호출(pg_net)에 필요한 확장
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
