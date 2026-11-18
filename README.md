# CareConnect

Flutter mobile scheduling for patients, doctors, clinic administrators, and platform administrators. Patients can search fictional demo clinics, view live slots, book without payment, reschedule, cancel, and read notifications. Clinic staff can register clinics, add verified doctors, set or remove weekly hours, deactivate providers, block days, view appointments, and close appointments. PostgreSQL owns booking integrity.

## Prerequisites

- Flutter 3.41.2 or newer with Dart 3.11, Android SDK; Xcode and CocoaPods for iOS.
- A Supabase project or Supabase CLI local stack.
- A Resend account or notification provider webhook for outbound messages. In-app notifications work without one.

## Local setup

1. Run `flutter pub get`.
2. Run `supabase start` from this repository (Docker required). The CLI applies migrations and `supabase/seed.sql`.
3. Copy the API URL and publishable key from `supabase status`. Only the publishable key goes in the app.
4. Run:

   ```sh
   flutter run --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
   ```

   Android emulator users normally use `http://10.0.2.2:54321` for the host API URL. A physical device needs a reachable host address and suitable HTTPS setup.

5. In Supabase Auth URL Configuration, allow `careconnect://auth-callback`. Email confirmation and password recovery use this link. For local development, open the email link in the local Inbucket UI. If confirming on a simulator, open the link on that simulator/device.
6. Create patient and doctor accounts, confirm their emails, register a clinic, add the doctor's verified email and specialty, then add weekly hours. The demo clinics are discovery samples; their fictional doctors are not associated with login accounts.

The app persists Supabase sessions in Keychain or encrypted Android storage through `flutter_secure_storage`; role navigation is convenience only and all private data is checked by RLS or trusted server functions.

## End-to-end workflow

1. A verified user registers a clinic and becomes its clinic administrator.
2. The administrator adds a previously verified doctor account, selects a specialty and consultation duration, and adds weekly hours. Clinic admins can edit contact details and booking cutoffs later.
3. A patient searches by doctor, specialty, clinic, or city and chooses an available day and time.
4. The booking RPC rechecks the slot and inserts the appointment. Database exclusion constraints reject overlapping doctor or patient bookings, including concurrent requests.
5. The doctor sees the booking in the clinic workspace. The patient sees it in My appointments and receives an in-app confirmation. A configured provider can deliver the generic confirmation and reminder externally.
6. The doctor marks the visit completed or no-show after it starts.

Clinic administrators can block full days or a doctor's day. Blocks overlapping existing bookings are rejected until those appointments are moved or cancelled. Cancellation and rescheduling cutoffs are per clinic. Times are shown in the device time zone; dates and schedules use the clinic's IANA time zone.

## Notifications

Deploy `dispatch-notifications` and set its secrets:

```sh
supabase functions deploy dispatch-notifications --no-verify-jwt
supabase secrets set CRON_SECRET=CHOOSE_A_LONG_RANDOM_VALUE
supabase secrets set RESEND_API_KEY=YOUR_RESEND_API_KEY
supabase secrets set NOTIFICATION_FROM_EMAIL='CareConnect <appointments@YOUR_VERIFIED_DOMAIN>'
# Or use a custom provider webhook instead:
# supabase secrets set NOTIFICATION_PROVIDER_URL=https://YOUR_PROVIDER_ENDPOINT
# supabase secrets set NOTIFICATION_PROVIDER_TOKEN=YOUR_PROVIDER_TOKEN
```

With Resend configured, the function sends generic confirmation, cancellation, reschedule, and reminder emails using its API and an idempotency key. A custom webhook takes precedence when `NOTIFICATION_PROVIDER_URL` is set; it receives `{user_id,email,kind,title,body}` and the `x-idempotency-key` notification ID. The webhook must authenticate its bearer token, deduplicate IDs, and deliver generic text only. No appointment time, provider, clinic, or patient condition is put in a push preview. If no external provider is set, rows remain visible in the in-app inbox and dispatch marks them delivered. Schedule a POST to `/functions/v1/dispatch-notifications` every minute with `Authorization: Bearer <CRON_SECRET>` using Supabase Cron or another trusted scheduler. [`supabase/scheduling.sql.example`](supabase/scheduling.sql.example) gives a Vault-backed cron example. Store the cron secret in Vault or an equivalent secret store, never in source control. Provider errors are retried with exponential backoff up to five attempts; failed rows remain available to administrators for investigation.

`delete-account` requires the caller's JWT and keeps its service role key only in the Edge Function environment:

```sh
supabase functions deploy delete-account
```

## Tests

```sh
flutter analyze
flutter test test
flutter build apk --debug
```

The SQL test suite can run on a disposable PostgreSQL 16 database: apply `supabase/tests/bootstrap.sql`, both migrations, and `supabase/seed.sql`; then run `supabase/tests/booking.sql`, `supabase/tests/workflows.sql`, and `scripts/test_concurrent_booking.sh` with `CARECONNECT_TEST_DATABASE_URL` set. The bootstrap file is **only** for plain PostgreSQL CI; never deploy it to Supabase. CI runs these checks and an unsigned iOS build. The integration test under `integration_test/` runs against a disposable Supabase project with a confirmed test patient and seed data. Run `flutter test integration_test/booking_journey_test.dart -d DEVICE_ID` with `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `TEST_PATIENT_EMAIL`, and `TEST_PATIENT_PASSWORD` supplied via `--dart-define`; it skips without them. The test signs in, finds a live slot, books it, verifies the appointment, and cancels it.

## Daily automated maintenance

GitHub Actions runs `.github/workflows/daily-health.yml` at 04:00 UTC (09:30 Asia/Kolkata). It resolves Flutter dependencies, runs analysis and unit/widget tests, and commits one dated report under `docs/maintenance/` using the `github-actions[bot]` identity. The report identifies the run and check results. A manual rerun on the same local date does not create another report. This workflow runs on GitHub while a developer's computer is off; it does not write application code or represent a day of manual development. Bot-authored reports are not expected to count as the repository owner's personal contribution activity. GitHub may delay or skip scheduled runs, and repository Actions settings or branch protection can prevent a push, so a commit every calendar day is not guaranteed. To stop the schedule, disable the workflow in GitHub Actions or remove its `schedule` trigger.

## Android and iOS builds

```sh
flutter build apk --release --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
flutter build appbundle --release --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
flutter build ios --release --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

For Android release signing, create a keystore outside source control and add `android/key.properties` with `storePassword`, `keyPassword`, `keyAlias`, and `storeFile` (path relative to `android/app`). The project reads this file only for release signing; without it, release artifacts are unsigned. Configure iOS bundle ID, team, signing, and provisioning in Xcode before store submission. The custom URL scheme is registered in both platform projects. Use release-specific secure redirect URLs for separate environments.

## Deployment

1. Create a Supabase project, enable email confirmation, set Auth redirect URLs, and configure outbound Auth email.
2. Link the CLI: `supabase link --project-ref PROJECT_REF`, then deploy SQL with `supabase db push`. Seed data is for development only; do not apply it to production.
3. Deploy both Edge Functions and configure secrets. The service role key is automatically available to hosted functions; never pass it to Flutter.
4. Schedule notification dispatch each minute. Schedule `select public.purge_expired_data();` daily using Supabase Cron with a privileged role.
5. Create platform administrators only through a trusted SQL operation inserting their auth user ID into `public.platform_administrators`.
6. Build signed Android and iOS releases with the production URL and publishable key.

## Privacy and operational review

This app collects scheduling identity, contact details, and appointment times only. It does not store diagnoses or clinical notes. Patient appointment details are protected by RLS; generic notification previews avoid sensitive information. Profile deletion is available in the app and removes the account and associated patient scheduling records. The retention function removes notifications after 90 days and closed appointments and audit entries after 730 days. Review and adjust these periods for applicable law and clinic policy before real use. A clinician, privacy officer, and security team must review regulatory requirements, consent language, breach response, backup deletion, processor agreements, email/push provider handling, audit retention, and access controls before handling real patient data. This repository has not undergone that review.

See [architecture](docs/architecture.md) for the component diagram and trust boundaries.
