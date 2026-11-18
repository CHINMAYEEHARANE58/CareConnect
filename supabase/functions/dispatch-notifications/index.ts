import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.118.0';

// Invoked by a trusted scheduler. External messages deliberately omit appointment details.
Deno.serve(async (request) => {
  const cronSecret = Deno.env.get('CRON_SECRET');
  if (!cronSecret || request.headers.get('authorization') !== `Bearer ${cronSecret}`) {
    return new Response('Unauthorized', { status: 401 });
  }
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const webhook = Deno.env.get('NOTIFICATION_PROVIDER_URL');
  const providerToken = Deno.env.get('NOTIFICATION_PROVIDER_TOKEN');
  const resendKey = Deno.env.get('RESEND_API_KEY');
  const fromEmail = Deno.env.get('NOTIFICATION_FROM_EMAIL');
  const { data: jobs, error } = await db.rpc('claim_notifications', { p_limit: 50 });
  if (error) return new Response(error.message, { status: 500 });
  let sent = 0;
  for (const job of jobs ?? []) {
    try {
      const { data: profile } = await db.from('profiles').select('notification_enabled').eq('id', job.user_id).single();
      if (profile?.notification_enabled && (webhook || resendKey || fromEmail)) {
        if (!webhook && (!resendKey || !fromEmail)) throw new Error('Email provider configuration incomplete');
        const { data: identity, error: identityError } = await db.auth.admin.getUserById(job.user_id);
        if (identityError || !identity.user?.email) throw new Error('Recipient unavailable');
        let response: Response;
        if (webhook) {
          response = await fetch(webhook, {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'x-idempotency-key': job.id, ...(providerToken ? { authorization: `Bearer ${providerToken}` } : {}) },
            body: JSON.stringify({ user_id: job.user_id, email: identity.user.email, kind: job.kind, title: job.title, body: job.body }),
          });
        } else {
          response = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: { 'content-type': 'application/json', authorization: `Bearer ${resendKey}`, 'Idempotency-Key': job.id },
            body: JSON.stringify({ from: fromEmail, to: [identity.user.email], subject: job.title, text: job.body }),
          });
        }
        if (!response.ok) throw new Error(`Provider returned ${response.status}`);
      }
      // Even without an external provider, the in-app inbox has the notification.
      const { error: markError } = await db.from('notifications').update({ delivered_at: new Date().toISOString(), delivery_locked_until: null, last_error: null }).eq('id', job.id);
      if (markError) throw markError;
      sent++;
    } catch (e) {
      const delayMinutes = Math.min(60, 2 ** job.attempts);
      const { error: retryError } = await db.from('notifications').update({
        deliver_after: new Date(Date.now() + delayMinutes * 60000).toISOString(),
        delivery_locked_until: null,
        last_error: String(e).slice(0, 500),
      }).eq('id', job.id);
      if (retryError) console.error('Could not reschedule notification', job.id, retryError.message);
    }
  }
  return Response.json({ claimed: jobs?.length ?? 0, sent });
});
