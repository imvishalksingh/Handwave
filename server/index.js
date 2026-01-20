const express = require('express');
const { createClient } = require('@supabase/supabase-js');
const rateLimit = require('express-rate-limit');
const cors = require('cors');
const helmet = require('helmet');
require('dotenv').config();

const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: ['http://localhost:3000', 'http://localhost:19006'], // React Native/Expo
  credentials: true
}));
app.use(express.json());

// Initialize Supabase
const supabaseUrl = process.env.APP_SUPABASE_URL;
const supabaseKey = process.env.APP_SUPABASE_SERVICE_ROLE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

// Rate limiting
const signalLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_SIGNALS_PER_HOUR) || 12,
  message: { error: 'Too many signals created. Please wait.' }
});

const pingLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_PINGS_PER_MINUTE) || 10,
  message: { error: 'Too many location updates.' }
});

// Auth middleware
const authenticate = async (req, res, next) => {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    if (!token) {
      return res.status(401).json({ error: 'No token provided' });
    }
    
    const { data: { user }, error } = await supabase.auth.getUser(token);
    if (error) throw error;
    
    req.user = user;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Invalid token' });
  }
};


const authenticateOptional = async (req, res, next) => {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    if (!token) {
      req.user = null; // Mark as Guest
      return next();
    }
    
    const { data: { user }, error } = await supabase.auth.getUser(token);
    req.user = error ? null : user;
    next();
  } catch (error) {
    req.user = null;
    next();
  }
};

// Utility functions
const roundLocation = (lat, lng) => {
  const precision = 4; // ~100m precision
  const factor = Math.pow(10, precision);
  return {
    lat: Math.round(lat * factor) / factor,
    lng: Math.round(lng * factor) / factor
  };
};

// ==================== API ENDPOINTS ====================

// 1. Health check
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// 2. Presence ping
app.post('/api/v1/presence/ping', pingLimiter, authenticateOptional, async (req, res) => {
  try {
    let { lat, lng, device_hash } = req.body;

    // 1. TYPE SAFETY: Convert to numbers immediately
    lat = parseFloat(lat);
    lng = parseFloat(lng);

    // 2. VALIDATION: Check for NaN (Invalid numbers), not just "falsy"
    if (isNaN(lat) || isNaN(lng)) {
        return res.status(400).json({ error: 'Valid numeric Location required' });
    }

    // 3. DEBUG LOG (Crucial for you right now)
    const ngeohash = require('ngeohash'); // Move require out if possible, but this works
    const searchGeohash = ngeohash.encode(lat, lng, 5);
    
    console.log(`📡 PING: ${lat}, ${lng} -> Searching Hash: ${searchGeohash}%`);

    // 4. SAVE LOCATION (If Logged In)
    if (req.user && req.user.id) {
        const saveGeohash = ngeohash.encode(lat, lng, 6);
        await supabase.rpc('update_user_presence', {
          p_user_id: req.user.id,
          p_geohash: saveGeohash,
          p_lat: lat,
          p_lng: lng,
          p_device_hash: device_hash || 'unknown'
        });
    }

    // 5. QUERY
    let query = supabase
      .from('user_presence')
      .select('lat, lng, geohash') // <--- Added geohash for debug visibility
      .eq('is_online', true)
      .like('geohash', `${searchGeohash}%`)
      .limit(50);

    if (req.user && req.user.id) {
        query = query.neq('user_id', req.user.id);
    }

    const { data: nearbyUsers, error } = await query;
    if (error) {
        console.error("❌ DB Query Error:", error);
        throw error;
    }

    console.log(`✅ FOUND: ${nearbyUsers?.length || 0} dots.`);

    // 6. FUZZING (Safe now because we parsed floats)
    const fuzzyDots = nearbyUsers?.map(u => ({
        lat: u.lat + (Math.random() - 0.5) * 0.005, 
        lng: u.lng + (Math.random() - 0.5) * 0.005
    })) || [];

    res.json({
      success: true,
      is_guest: !req.user,
      nearby_dots: fuzzyDots 
    });

  } catch (error) {
    console.error('Ping error:', error);
    res.status(500).json({ error: error.message });
  }
});
// 3. Create signal
app.post('/api/v1/signals/create', signalLimiter, authenticate, async (req, res) => {
  try {
    const { lat, lng, radius = 1000, boost_type } = req.body;
    
    // Check user's daily limit
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('signals_today, subscription_tier')
      .eq('auth_id', req.user.id)
      .single();
    
    if (userError) {
      // Create user record if doesn't exist
      await supabase
        .from('users')
        .insert({
          auth_id: req.user.id,
          display_name: `User_${req.user.id.slice(0, 8)}`,
          signals_today: 0
        });
    }
    
    const limit = userData?.subscription_tier === 'free' ? 10 : 
                  userData?.subscription_tier === 'plus' ? 30 : 100;
    
    if (userData?.signals_today >= limit) {
      return res.status(429).json({ 
        error: 'Daily signal limit reached',
        upgrade_required: true 
      });
    }
    
    const rounded = roundLocation(lat, lng);
    const geohash = require('ngeohash').encode(rounded.lat, rounded.lng, 6);
    
    // Create signal
    const { data: signal, error: signalError } = await supabase
      .from('signals')
      .insert({
        user_id: req.user.id,
        geohash: geohash,
        lat: rounded.lat,
        lng: rounded.lng,
        visibility_radius_meters: Math.min(radius, parseInt(process.env.MAX_DISTANCE_METERS) || 5000),
        signal_type: boost_type ? 'boosted' : 'standard',
        expires_at: new Date(Date.now() + 120000).toISOString()
      })
      .select()
      .single();
    
    if (signalError) throw signalError;
    
    // Update user's signal count
    await supabase
      .from('users')
      .update({ 
        signals_today: (userData?.signals_today || 0) + 1,
        last_signal_at: new Date().toISOString()
      })
      .eq('auth_id', req.user.id);
    
    res.json({
      success: true,
      signal_id: signal.id,
      expires_at: signal.expires_at,
      estimated_match_time: '30s'
    });
  } catch (error) {
    console.error('Create signal error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 4. Get pending matches
app.get('/api/v1/matches/pending', authenticate, async (req, res) => {
  try {
    const { data: matches, error } = await supabase
      .from('mutual_signals')
      .select(`
        id,
        created_at,
        expires_at,
        distance_meters,
        user_a_id,
        user_b_id,
        user_a_acknowledged,
        user_b_acknowledged,
        status
      `)
      .or(`user_a_id.eq.${req.user.id},user_b_id.eq.${req.user.id}`)
      .eq('status', 'pending')
      .gt('expires_at', new Date().toISOString());
    
    if (error) throw error;
    
    const formatted = matches.map(match => ({
      mutual_signal_id: match.id,
      expires_at: match.expires_at,
      other_user_id: match.user_a_id === req.user.id ? match.user_b_id : match.user_a_id,
      acknowledged: match.user_a_id === req.user.id ? match.user_a_acknowledged : match.user_b_acknowledged,
      distance_meters: match.distance_meters,
      time_remaining: Math.max(0, new Date(match.expires_at) - Date.now())
    }));
    
    res.json({ matches: formatted });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 5. Accept match
app.post('/api/v1/matches/:id/accept', authenticate, async (req, res) => {
  try {
    const mutualSignalId = req.params.id;
    
    const { data: match, error: matchError } = await supabase
      .from('mutual_signals')
      .select('*')
      .eq('id', mutualSignalId)
      .single();
    
    if (matchError) throw matchError;
    
    // Check if user is participant
    if (![match.user_a_id, match.user_b_id].includes(req.user.id)) {
      return res.status(403).json({ error: 'Not authorized' });
    }
    
    // Update acknowledgment
    const updateField = match.user_a_id === req.user.id ? 'user_a_acknowledged' : 'user_b_acknowledged';
    
    const { data: updated, error: updateError } = await supabase
      .from('mutual_signals')
      .update({ [updateField]: true })
      .eq('id', mutualSignalId)
      .select()
      .single();
    
    if (updateError) throw updateError;
    
    // If both acknowledged, create reveal
    if (updated.user_a_acknowledged && updated.user_b_acknowledged) {
      await supabase
        .from('mutual_signals')
        .update({ status: 'accepted' })
        .eq('id', mutualSignalId);
      
      // Create reveals for both users
      const revealExpiry = new Date(Date.now() + 15 * 60 * 1000).toISOString();
      
      await supabase
        .from('reveals')
        .insert([
          {
            mutual_signal_id: mutualSignalId,
            viewer_id: match.user_a_id,
            viewed_id: match.user_b_id,
            expires_at: revealExpiry
          },
          {
            mutual_signal_id: mutualSignalId,
            viewer_id: match.user_b_id,
            viewed_id: match.user_a_id,
            expires_at: revealExpiry
          }
        ]);
      
      // Get other user's profile
      const otherUserId = match.user_a_id === req.user.id ? match.user_b_id : match.user_a_id;
      const { data: otherUser } = await supabase
        .from('users')
        .select('display_name, avatar_url, short_bio')
        .eq('id', otherUserId)
        .single();
      
      res.json({
        success: true,
        reveal_created: true,
        other_user_profile: otherUser || { display_name: 'Anonymous' },
        reveal_expires_at: revealExpiry
      });
    } else {
      res.json({
        success: true,
        reveal_created: false,
        waiting_for_other: true
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 6. Decline match
app.post('/api/v1/matches/:id/decline', authenticate, async (req, res) => {
  try {
    const mutualSignalId = req.params.id;
    
    const { data: match } = await supabase
      .from('mutual_signals')
      .select('*')
      .eq('id', mutualSignalId)
      .single();
    
    if (![match.user_a_id, match.user_b_id].includes(req.user.id)) {
      return res.status(403).json({ error: 'Not authorized' });
    }
    
    const updateField = match.user_a_id === req.user.id ? 'user_a_declined' : 'user_b_declined';
    
    await supabase
      .from('mutual_signals')
      .update({ 
        [updateField]: true,
        status: 'declined'
      })
      .eq('id', mutualSignalId);
    
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 7. Send message
app.post('/api/v1/interactions/message', authenticate, async (req, res) => {
  try {
    const { reveal_id, content } = req.body;
    
    // Verify reveal exists and user has access
    const { data: reveal, error: revealError } = await supabase
      .from('reveals')
      .select('*')
      .eq('id', reveal_id)
      .or(`viewer_id.eq.${req.user.id},viewed_id.eq.${req.user.id}`)
      .gt('expires_at', new Date().toISOString())
      .single();
    
    if (revealError) {
      return res.status(404).json({ error: 'Reveal not found or expired' });
    }
    
    const receiver_id = reveal.viewer_id === req.user.id ? reveal.viewed_id : reveal.viewer_id;
    
    // Create message
    const { data: message, error } = await supabase
      .from('interactions')
      .insert({
        reveal_id,
        sender_id: req.user.id,
        receiver_id,
        interaction_type: 'message',
        content,
        expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString()
      })
      .select()
      .single();
    
    if (error) throw error;
    
    // Send realtime notification via Supabase
    await supabase.channel(`user:${receiver_id}`)
      .send({
        type: 'broadcast',
        event: 'new_message',
        payload: {
          interaction_id: message.id,
          sender_id: req.user.id,
          content,
          created_at: message.created_at
        }
      });
    
    res.json({ success: true, interaction_id: message.id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 8. Get active reveals
app.get('/api/v1/reveals/active', authenticate, async (req, res) => {
  try {
    const { data: reveals, error } = await supabase
      .from('reveals')
      .select(`
        id,
        viewed_id,
        expires_at,
        last_viewed_at,
        users!reveals_viewed_id_fkey(display_name, avatar_url, short_bio)
      `)
      .eq('viewer_id', req.user.id)
      .gt('expires_at', new Date().toISOString())
      .order('expires_at', { ascending: true });
    
    if (error) throw error;
    
    res.json({ reveals: reveals || [] });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 9. Report user
app.post('/api/v1/reports/create', authenticate, async (req, res) => {
  try {
    const { reported_user_id, report_type, description, signal_id, interaction_id } = req.body;
    
    // Check rate limit for reports
    const { count } = await supabase
      .from('reports')
      .select('*', { count: 'exact', head: true })
      .eq('reporter_id', req.user.id)
      .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
    
    if (count >= (parseInt(process.env.RATE_LIMIT_REPORTS_PER_DAY) || 5)) {
      return res.status(429).json({ error: 'Daily report limit reached' });
    }
    
    // Create report
    const { data: report, error } = await supabase
      .from('reports')
      .insert({
        reporter_id: req.user.id,
        reported_user_id,
        reported_signal_id: signal_id,
        reported_interaction_id: interaction_id,
        report_type,
        description,
        device_hash: req.headers['device-hash'],
        ip_address: req.ip
      })
      .select()
      .single();
    
    if (error) throw error;
    
    // Update reported user's score
    await supabase
      .from('users')
      .update({ 
        report_score: () => 'report_score - 1'
      })
      .eq('id', reported_user_id);
    
    res.json({ success: true, report_id: report.id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 10. Create user (Public Signup with Email Verification)
app.post('/api/v1/users/create', async (req, res) => {
  try {
    // 1. Accept new fields from the UI
    const { email, password, display_name, avatar_url, short_bio, age_range, interests } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    // 2. Use signUp() to trigger standard email verification
    // This respects your Supabase project settings (Project Settings -> Auth -> Email -> "Enable Email Confirmations")
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email: email,
      password: password,
      options: {
        data: {
          display_name: display_name || `User_${Date.now().toString().slice(-6)}`
        }
      }
    });

    if (authError) throw authError;

    // Guard clause: If signUp returns no user (rare, but possible depending on config)
    if (!authData.user) {
        return res.status(400).json({ error: 'User creation failed' });
    }

    // 3. Create profile in public.users table immediately
    // We use 'upsert' here. If the user clicked signup twice, this updates the profile instead of crashing.
    const { data: profile, error: profileError } = await supabase
      .from('users')
      .upsert({
        auth_id: authData.user.id,
        display_name: display_name || `User_${authData.user.id.slice(0, 8)}`,
        avatar_url: avatar_url,
        short_bio: short_bio,
        
        // NEW FIELDS FROM UI
        age_range: age_range,
        interests: interests || [], 
        
        subscription_tier: 'free',
        max_distance_meters: 1000,
        visibility_preference: 'balanced',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      }, { onConflict: 'auth_id' })
      .select()
      .single();

    if (profileError) {
      // If the profile creation fails, we might want to log it or handle cleanup.
      // For now, we throw to the error handler.
      throw profileError;
    }

    // 4. Return success message (IMPORTANT: No Access Token returned)
    // We cannot return a token because the user hasn't verified their email yet.
    // The Frontend should show a "Check your email" screen.
    res.json({
      success: true,
      message: 'Signup successful. Please check your email to verify your account.',
      user: profile,
      email_sent: true,
      requires_verification: true
    });

  } catch (error) {
    console.error('Create user error:', error);
    res.status(500).json({ error: error.message });
  }
});



// 10. Get user profile
app.get('/api/v1/user/profile', authenticate, async (req, res) => {
  try {
    const { data: profile, error } = await supabase
      .from('users')
      .select('display_name, avatar_url, short_bio, subscription_tier, signals_today')
      .eq('auth_id', req.user.id)
      .single();
    
    if (error) throw error;
    
    res.json({ profile });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 11. Update user profile
app.patch('/api/v1/user/profile', authenticate, async (req, res) => {
  try {
    const { display_name, avatar_url, short_bio } = req.body;
    
    const updates = {};
    if (display_name) updates.display_name = display_name;
    if (avatar_url) updates.avatar_url = avatar_url;
    if (short_bio) updates.short_bio = short_bio;
    
    const { data, error } = await supabase
      .from('users')
      .update(updates)
      .eq('auth_id', req.user.id)
      .select()
      .single();
    
    if (error) throw error;
    
    res.json({ success: true, profile: data });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 12. Get user stats
app.get('/api/v1/user/stats', authenticate, async (req, res) => {
  try {
    const { data: user } = await supabase
      .from('users')
      .select('signals_today, last_signal_at, subscription_tier, created_at')
      .eq('auth_id', req.user.id)
      .single();
    
    // Get match statistics
    const { count: totalMatches } = await supabase
      .from('mutual_signals')
      .select('*', { count: 'exact', head: true })
      .or(`user_a_id.eq.${req.user.id},user_b_id.eq.${req.user.id}`);
    
    const { count: successfulMatches } = await supabase
      .from('mutual_signals')
      .select('*', { count: 'exact', head: true })
      .or(`user_a_id.eq.${req.user.id},user_b_id.eq.${req.user.id}`)
      .eq('status', 'accepted');
    
    res.json({
      signals_today: user?.signals_today || 0,
      total_matches: totalMatches || 0,
      successful_matches: successfulMatches || 0,
      account_age_days: Math.floor((Date.now() - new Date(user?.created_at).getTime()) / (1000 * 60 * 60 * 24)),
      subscription_tier: user?.subscription_tier || 'free'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📡 API available at http://localhost:${PORT}/api`);
});
