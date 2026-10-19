-- 매시 20분(기상청 단기예보 발표 +15분 이후)에 refresh 함수를 호출한다.
-- Vault 값은 저장소에 두지 않고 사용자가 SQL Editor에서 한 번 등록한다(docs/setup.md):
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<SPIKE_TOKEN 값>', 'spike_token');
select cron.schedule(
  'weatherbridge-refresh',
  '20 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
      || '/functions/v1/refresh?async=1',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-spike-token', (select decrypted_secret from vault.decrypted_secrets where name = 'spike_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  ) as request_id;
  $$
);
