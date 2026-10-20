-- 매분 dispatch 호출. 누구에게 보낼지(요약 시각·중복)는 함수가 판단한다(schedule.ts, 테스트됨).
-- refresh와 같이 Vault의 project_url·spike_token을 쓰고, 함수는 즉시 202를 돌려준 뒤 백그라운드로 처리한다.
select cron.schedule(
  'weatherbridge-dispatch',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
      || '/functions/v1/dispatch?async=1',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-spike-token', (select decrypted_secret from vault.decrypted_secrets where name = 'spike_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  ) as request_id;
  $$
);

-- 매분 잡이 생기면 실행 기록이 하루 1,440건씩 쌓이므로 7일만 남긴다.
select cron.schedule(
  'weatherbridge-cron-cleanup',
  '13 3 * * *',
  $$ delete from cron.job_run_details where end_time < now() - interval '7 days' $$
);
