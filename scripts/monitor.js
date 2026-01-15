const { createClient } = require('@supabase/supabase-js')
require('dotenv').config()

async function monitor() {
  const supabase = createClient(
    process.env.APP_SUPABASE_URL,
    process.env.APP_SUPABASE_SERVICE_ROLE_KEY
  )

  console.log('📊 SYSTEM MONITORING REPORT')
  console.log('===========================\n')
  
  const now = new Date().toISOString()
  
  // Get active users count
  const { count: activeUsers } = await supabase
    .from('user_presence')
    .select('*', { count: 'exact', head: true })
    .eq('is_online', true)
    .gt('expires_at', now)
  
  // Get active signals
  const { count: activeSignals } = await supabase
    .from('signals')
    .select('*', { count: 'exact', head: true })
    .eq('status', 'active')
    .gt('expires_at', now)
  
  // Get pending matches
  const { count: pendingMatches } = await supabase
    .from('mutual_signals')
    .select('*', { count: 'exact', head: true })
    .eq('status', 'pending')
    .gt('expires_at', now)
  
  // Get recent reports
  const { count: recentReports } = await supabase
    .from('reports')
    .select('*', { count: 'exact', head: true })
    .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
  
  console.log('Live Stats:')
  console.log(`✅ Active users: ${activeUsers || 0}`)
  console.log(`📶 Active signals: ${activeSignals || 0}`)
  console.log(`🤝 Pending matches: ${pendingMatches || 0}`)
  console.log(`🚨 Recent reports (24h): ${recentReports || 0}`)
  
  // Check for issues
  const issues = []
  
  if ((activeSignals || 0) > 50) {
    issues.push('High number of active signals - consider scaling')
  }
  
  if ((recentReports || 0) > 10) {
    issues.push('High number of reports - check moderation')
  }
  
  if (issues.length > 0) {
    console.log('\n⚠️  ISSUES DETECTED:')
    issues.forEach(issue => console.log(`   • ${issue}`))
  } else {
    console.log('\n✅ All systems normal')
  }
  
  console.log('\n📈 Recommendations:')
  console.log('1. Check database performance in Supabase dashboard')
  console.log('2. Review recent reports for patterns')
  console.log('3. Monitor error logs in deployment platform')
  console.log('4. Consider upgrading plan if approaching limits')
}

monitor()
