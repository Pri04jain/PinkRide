const { createClient } = require('@supabase/supabase-js');

// Supabase client — uses the service role key for backend operations
// This bypasses Row Level Security (RLS), which is what we want on the server
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

/**
 * Run a raw SQL query via Supabase's rpc or REST interface.
 * For most operations, use the supabase query builder directly.
 * Export the client so services can use it directly.
 */
module.exports = { supabase };
