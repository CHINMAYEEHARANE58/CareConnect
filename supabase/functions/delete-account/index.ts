import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.118.0';

Deno.serve(async (request) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return new Response('Unauthorized', { status: 401 });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: { user }, error } = await admin.auth.getUser(authorization.slice(7));
  if (error || !user) return new Response('Unauthorized', { status: 401 });

  const { data: doctor } = await admin.from('doctors').select('id').eq('profile_id', user.id).maybeSingle();
  if (doctor) {
    const { error: cancelDoctor } = await admin.from('appointments').update({ status: 'cancelled' }).eq('doctor_id', doctor.id).eq('status', 'booked');
    if (cancelDoctor) return new Response(cancelDoctor.message, { status: 500 });
    const { error: deactivate } = await admin.from('doctors').update({ active: false }).eq('id', doctor.id);
    if (deactivate) return new Response(deactivate.message, { status: 500 });
  }
  const { data: memberships } = await admin.from('clinic_memberships').select('clinic_id').eq('user_id', user.id).eq('role', 'clinic_admin');
  for (const member of memberships ?? []) {
    const { count } = await admin.from('clinic_memberships').select('*', { count: 'exact', head: true }).eq('clinic_id', member.clinic_id).eq('role', 'clinic_admin').neq('user_id', user.id);
    if ((count ?? 0) === 0) {
      const { error: cancelClinic } = await admin.from('appointments').update({ status: 'cancelled' }).eq('clinic_id', member.clinic_id).eq('status', 'booked');
      if (cancelClinic) return new Response(cancelClinic.message, { status: 500 });
      const { error: deactivate } = await admin.from('clinics').update({ active: false }).eq('id', member.clinic_id);
      if (deactivate) return new Response(deactivate.message, { status: 500 });
    }
  }
  const { error: cancelPatient } = await admin.from('appointments').update({ status: 'cancelled' }).eq('patient_id', user.id).eq('status', 'booked');
  if (cancelPatient) return new Response(cancelPatient.message, { status: 500 });
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return new Response(deleteError.message, { status: 500 });
  return Response.json({ deleted: true });
});
