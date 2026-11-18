#!/usr/bin/env bash
set -euo pipefail
: "${CARECONNECT_TEST_DATABASE_URL:?Set CARECONNECT_TEST_DATABASE_URL to a disposable PostgreSQL database URL}"
psql "$CARECONNECT_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('cccccccc-cccc-4ccc-8ccc-cccccccccccc','race1@example.invalid',now(),'{}'),
('dddddddd-dddd-4ddd-8ddd-dddddddddddd','race2@example.invalid',now(),'{}');
SQL
cleanup() {
  psql "$CARECONNECT_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -c "delete from auth.users where id in ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','dddddddd-dddd-4ddd-8ddd-dddddddddddd')" >/dev/null
}
trap cleanup EXIT
slot=$(psql "$CARECONNECT_TEST_DATABASE_URL" -Atq -c "select starts_at from public.available_slots('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',(current_date+(8-extract(dow from current_date)::int))::date) limit 1")
if [[ -z "$slot" ]]; then echo 'No test slot available'; exit 1; fi
book() {
  local patient_id="$1"
  psql "$CARECONNECT_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -v chosen_slot="$slot" <<SQL >/dev/null 2>&1
set request.jwt.claim.sub='$patient_id';
set role authenticated;
select public.book_appointment('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',:'chosen_slot');
SQL
}
book 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' & first=$!
book 'dddddddd-dddd-4ddd-8ddd-dddddddddddd' & second=$!
set +e
wait "$first"; first_result=$?
wait "$second"; second_result=$?
set -e
if [[ $(( (first_result == 0) + (second_result == 0) )) -ne 1 ]]; then
  echo "Expected exactly one booking success; got $first_result and $second_result"; exit 1
fi
count=$(psql "$CARECONNECT_TEST_DATABASE_URL" -Atq -v chosen_slot="$slot" <<'SQL'
select count(*) from public.appointments where starts_at=:'chosen_slot' and patient_id in ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','dddddddd-dddd-4ddd-8ddd-dddddddddddd');
SQL
)
if [[ "$count" != '1' ]]; then echo "Expected one persisted booking, got $count"; exit 1; fi
echo 'Concurrent booking race: one booking succeeded, one was rejected.'
