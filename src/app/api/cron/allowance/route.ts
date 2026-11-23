import { NextResponse } from 'next/server'
import { getSupabaseAdmin } from '@/lib/supabase_admin'

// Backup trigger for the daily allowance. The dashboard also calls
// ensure_allowance on load, and the function is idempotent, so running this
// more than once (or not at all on some day) never double-adds or loses a day.
export async function GET(request: Request) {
  const cronSecret = process.env.CRON_SECRET
  const authHeader = request.headers.get('authorization')
  if (!cronSecret || authHeader !== `Bearer ${cronSecret}`) {
    return new NextResponse('Unauthorized', { status: 401 })
  }

  const ownerId = process.env.TRACKR_OWNER_ID
  if (!ownerId) {
    return NextResponse.json({ error: 'Missing TRACKR_OWNER_ID' }, { status: 500 })
  }

  const { data, error } = await getSupabaseAdmin().rpc('ensure_allowance', { p_user_id: ownerId })
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ success: true, daysAdded: data })
}
