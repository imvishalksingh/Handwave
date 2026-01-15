// Follow this setup guide: https://supabase.com/docs/guides/functions

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify secret key
    const authHeader = req.headers.get('Authorization')
    const secret = Deno.env.get('CRON_SECRET')
    
    if (authHeader !== `Bearer ${secret}`) {
      return new Response('Unauthorized', { status: 401 })
    }

    const supabaseUrl = Deno.env.get('APP_SUPABASE_URL')!
    const supabaseKey = Deno.env.get('APP_SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    const now = new Date().toISOString()
    const oneHourAgo = new Date(Date.now() - 3600000).toISOString()
    const oneDayAgo = new Date(Date.now() - 86400000).toISOString()

    const tasks = [
      // 1. Expire old signals
      async () => {
        const { error } = await supabase
          .from('signals')
          .update({ status: 'expired' })
          .eq('status', 'active')
          .lt('expires_at', now)
        
        return { task: 'expire_signals', error: error?.message }
      },

      // 2. Clean expired mutual signals
      async () => {
        const { error } = await supabase
          .from('mutual_signals')
          .delete()
          .lt('expires_at', oneHourAgo)
        
        return { task: 'clean_mutual_signals', error: error?.message }
      },

      // 3. Update offline users
      async () => {
        const { error } = await supabase
          .from('user_presence')
          .update({ is_online: false })
          .lt('expires_at', now)
        
        return { task: 'update_offline_users', error: error?.message }
      },

      // 4. Delete old presence records
      async () => {
        const { error } = await supabase
          .from('user_presence')
          .delete()
          .lt('expires_at', oneDayAgo)
        
        return { task: 'clean_old_presence', error: error?.message }
      },

      // 5. Delete expired interactions
      async () => {
        const { error } = await supabase
          .from('interactions')
          .delete()
          .lt('expires_at', now)
        
        return { task: 'clean_interactions', error: error?.message }
      },

      // 6. Delete expired reveals
      async () => {
        const { error } = await supabase
          .from('reveals')
          .delete()
          .lt('expires_at', now)
        
        return { task: 'clean_reveals', error: error?.message }
      },

      // 7. Reset daily counts at midnight UTC
      async () => {
        const utcHour = new Date().getUTCHours()
        if (utcHour === 0) { // Midnight UTC
          const { error } = await supabase
            .from('users')
            .update({ signals_today: 0 })
            .gt('signals_today', 0)
          
          return { task: 'reset_daily_counts', error: error?.message }
        }
        return { task: 'reset_daily_counts', skipped: 'not_midnight' }
      }
    ]

    // Execute all cleanup tasks
    const results = []
    for (const task of tasks) {
      try {
        const result = await task()
        results.push(result)
      } catch (error) {
        results.push({ error: error.message })
      }
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        timestamp: now,
        results 
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      }
    )

  } catch (error) {
    console.error('Cleanup error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    )
  }
})
