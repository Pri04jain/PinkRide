require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);

const drivers = [
  { phone:'9811122233', name:'Sunita Mehra',  license:'RJ0120180023401', vnum:'RJ14CD5600', make:'Hyundai', model:'i20',     color:'Silver', year:2021 },
  { phone:'9822233344', name:'Kavya Sharma',  license:'RJ0120190034501', vnum:'RJ14EF9000', make:'Maruti',  model:'Baleno',  color:'Red',    year:2020 },
  { phone:'9833344455', name:'Priya Agarwal', license:'RJ0120210045601', vnum:'RJ14GH3400', make:'Tata',    model:'Nexon EV',color:'White',  year:2023 },
];

(async () => {
  for (const d of drivers) {
    // Upsert user with driver role
    const { data: existing } = await sb.from('users').select('id').eq('phone', d.phone).maybeSingle();
    let uid;
    if (existing) {
      await sb.from('users').update({ role:'driver', full_name: d.name, face_verified: true }).eq('id', existing.id);
      uid = existing.id;
    } else {
      const { data, error } = await sb.from('users').insert({
        phone: d.phone, country_code:'+91', role:'driver',
        full_name: d.name, is_active:true, is_phone_verified:true,
        face_verified:true, city:'Jaipur'
      }).select('id').single();
      if (error) { console.log('user error:', error.message); continue; }
      uid = data.id;
    }

    // Check if driver profile exists
    const { data: dp } = await sb.from('drivers').select('id').eq('user_id', uid).maybeSingle();
    if (dp) {
      await sb.from('drivers').update({ approval_status:'under_review' }).eq('id', dp.id);
      console.log('Updated to under_review:', d.name);
    } else {
      const { error } = await sb.from('drivers').insert({
        user_id: uid, license_number: d.license, license_expiry:'2031-01-01',
        license_doc_url:'https://picsum.photos/400/300',
        vehicle_number: d.vnum, vehicle_type:'Hatchback',
        vehicle_make: d.make, vehicle_model: d.model,
        vehicle_color: d.color, vehicle_year: d.year,
        vehicle_rc_url:'https://picsum.photos/400/300',
        approval_status:'under_review',
      });
      if (error) console.log('driver error:', error.message);
      else console.log('Created under_review driver:', d.name);
    }
  }
  console.log('\nDone! Run: node demo/server.js and refresh the dashboard.');
  process.exit(0);
})();
