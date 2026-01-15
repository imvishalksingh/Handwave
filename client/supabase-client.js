import { createClient } from '@supabase/supabase-js'
import AsyncStorage from '@react-native-async-storage/async-storage'

// Initialize Supabase client for React Native
const supabaseUrl = 'YOUR_APP_SUPABASE_URL_HERE'
const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY_HERE'

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false
  }
})

// Helper function to update presence
export const updatePresence = async (latitude, longitude, deviceHash) => {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) throw new Error('Not authenticated')
    
    const response = await fetch(`${supabaseUrl}/api/v1/presence/ping`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        lat: latitude,
        lng: longitude,
        device_hash: deviceHash
      })
    })
    
    return await response.json()
  } catch (error) {
    console.error('Update presence error:', error)
    return { success: false, error: error.message }
  }
}

// Create signal
export const createSignal = async (latitude, longitude, radius = 1000) => {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) throw new Error('Not authenticated')
    
    const response = await fetch(`${supabaseUrl}/api/v1/signals/create`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        lat: latitude,
        lng: longitude,
        radius: radius
      })
    })
    
    return await response.json()
  } catch (error) {
    console.error('Create signal error:', error)
    return { success: false, error: error.message }
  }
}

// Subscribe to realtime updates
export const subscribeToRealtime = (userId, callbacks) => {
  const channel = supabase.channel(`user:${userId}`)
  
  if (callbacks.onNewMessage) {
    channel.on('broadcast', { event: 'new_message' }, callbacks.onNewMessage)
  }
  
  if (callbacks.onMatchFound) {
    channel.on('broadcast', { event: 'match_found' }, callbacks.onMatchFound)
  }
  
  if (callbacks.onRevealCreated) {
    channel.on('broadcast', { event: 'reveal_created' }, callbacks.onRevealCreated)
  }
  
  channel.subscribe((status) => {
    console.log('Realtime status:', status)
  })
  
  return channel
}

// Accept match
export const acceptMatch = async (mutualSignalId) => {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) throw new Error('Not authenticated')
    
    const response = await fetch(`${supabaseUrl}/api/v1/matches/${mutualSignalId}/accept`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type': 'application/json'
      }
    })
    
    return await response.json()
  } catch (error) {
    console.error('Accept match error:', error)
    return { success: false, error: error.message }
  }
}

// Send message
export const sendMessage = async (revealId, content) => {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) throw new Error('Not authenticated')
    
    const response = await fetch(`${supabaseUrl}/api/v1/interactions/message`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        reveal_id: revealId,
        content: content
      })
    })
    
    return await response.json()
  } catch (error) {
    console.error('Send message error:', error)
    return { success: false, error: error.message }
  }
}
