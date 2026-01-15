-- ==============================================
-- TEST DATA SEED SCRIPT
-- For Digital Hand Signal App
-- ==============================================

-- Enable necessary extensions if not already enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- Clear existing test data
DO $$ 
BEGIN
    RAISE NOTICE 'Cleaning up existing test data...';
    
    -- Delete in correct order (respecting foreign key constraints)
    DELETE FROM reports WHERE reporter_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    DELETE FROM boosts WHERE user_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    DELETE FROM subscriptions WHERE user_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    DELETE FROM interactions WHERE sender_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    ) OR receiver_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    DELETE FROM reveals WHERE viewer_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    ) OR viewed_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    DELETE FROM mutual_signals WHERE user_a_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    ) OR user_b_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    DELETE FROM signals WHERE user_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    DELETE FROM user_presence WHERE user_id IN (
        SELECT id FROM users WHERE display_name LIKE '%Test%' 
        OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
    );
    
    -- Delete test users
    DELETE FROM users WHERE display_name LIKE '%Test%' 
    OR display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm');
    
    RAISE NOTICE 'Cleanup complete!';
END $$;

-- ==============================================
-- CREATE TEST USERS
-- ==============================================

DO $$
DECLARE
    user1_id UUID;
    user2_id UUID;
    user3_id UUID;
    signal1_id UUID;
    signal2_id UUID;
    mutual_signal_id UUID;
    reveal_id UUID;
BEGIN
    RAISE NOTICE 'Creating test users...';
    
    -- User 1: Alex Johnson
    INSERT INTO users (
        auth_id,
        display_name,
        avatar_url,
        short_bio,
        max_distance_meters,
        visibility_preference,
        signals_today,
        subscription_tier,
        created_at
    ) VALUES (
        gen_random_uuid(),  -- Mock auth_id using gen_random_uuid()
        'Alex Johnson',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=Alex',
        'Digital nomad exploring coffee shops. Love tech and travel!',
        1500,
        'balanced',
        2,
        'plus',
        NOW() - INTERVAL '30 days'
    ) RETURNING id INTO user1_id;
    
    -- User 2: Sam CoffeeLover
    INSERT INTO users (
        auth_id,
        display_name,
        avatar_url,
        short_bio,
        max_distance_meters,
        visibility_preference,
        signals_today,
        subscription_tier,
        created_at
    ) VALUES (
        gen_random_uuid(),  -- Mock auth_id using gen_random_uuid()
        'Sam CoffeeLover',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=Sam',
        'Barista by day, gamer by night. Always up for coffee chat!',
        1000,
        'visible',
        5,
        'free',
        NOW() - INTERVAL '15 days'
    ) RETURNING id INTO user2_id;
    
    -- User 3: Taylor Bookworm
    INSERT INTO users (
        auth_id,
        display_name,
        avatar_url,
        short_bio,
        max_distance_meters,
        visibility_preference,
        signals_today,
        subscription_tier,
        created_at
    ) VALUES (
        gen_random_uuid(),  -- Mock auth_id using gen_random_uuid()
        'Taylor Bookworm',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=Taylor',
        'Reading at the park. Love sci-fi and fantasy novels!',
        800,
        'discreet',
        1,
        'premium',
        NOW() - INTERVAL '10 days'
    ) RETURNING id INTO user3_id;
    
    RAISE NOTICE 'Users created with IDs: %, %, %', user1_id, user2_id, user3_id;
    
    -- ==============================================
    -- CREATE PRESENCE RECORDS
    -- ==============================================
    
    RAISE NOTICE 'Creating presence records...';
    
    -- User 1 is online at downtown location
    INSERT INTO user_presence (
        user_id,
        geohash,
        lat,
        lng,
        device_hash,
        is_online,
        last_ping_at,
        expires_at
    ) VALUES (
        user1_id,
        '9q8yyk',
        37.7749,
        -122.4194,
        'device-alex-123',
        true,
        NOW(),
        NOW() + INTERVAL '5 minutes'
    );
    
    -- User 2 is online at same location (will match)
    INSERT INTO user_presence (
        user_id,
        geohash,
        lat,
        lng,
        device_hash,
        is_online,
        last_ping_at,
        expires_at
    ) VALUES (
        user2_id,
        '9q8yyk',
        37.7749,
        -122.4194,
        'device-sam-456',
        true,
        NOW(),
        NOW() + INTERVAL '5 minutes'
    );
    
    -- User 3 is online nearby
    INSERT INTO user_presence (
        user_id,
        geohash,
        lat,
        lng,
        device_hash,
        is_online,
        last_ping_at,
        expires_at
    ) VALUES (
        user3_id,
        '9q8yym',
        37.7752,
        -122.4189,
        'device-taylor-789',
        true,
        NOW(),
        NOW() + INTERVAL '3 minutes'
    );
    
    -- ==============================================
    -- CREATE SIGNALS
    -- ==============================================
    
    RAISE NOTICE 'Creating signals...';
    
    -- User 1 signal (active)
    INSERT INTO signals (
        user_id,
        geohash,
        lat,
        lng,
        signal_type,
        visibility_radius_meters,
        status,
        created_at,
        expires_at
    ) VALUES (
        user1_id,
        '9q8yyk',
        37.7749,
        -122.4194,
        'standard',
        1000,
        'active',
        NOW() - INTERVAL '30 seconds',
        NOW() + INTERVAL '90 seconds'
    ) RETURNING id INTO signal1_id;
    
    -- User 2 signal (active at same location - will match)
    INSERT INTO signals (
        user_id,
        geohash,
        lat,
        lng,
        signal_type,
        visibility_radius_meters,
        status,
        created_at,
        expires_at
    ) VALUES (
        user2_id,
        '9q8yyk',
        37.7749,
        -122.4194,
        'boosted',
        1500,
        'active',
        NOW() - INTERVAL '25 seconds',
        NOW() + INTERVAL '95 seconds'
    ) RETURNING id INTO signal2_id;
    
    RAISE NOTICE 'Signals created: % and %', signal1_id, signal2_id;
    
    -- ==============================================
    -- CREATE MANUAL MATCH (since trigger might not fire in seed)
    -- ==============================================
    
    RAISE NOTICE 'Creating mutual signal...';
    
    INSERT INTO mutual_signals (
        signal_a_id,
        signal_b_id,
        user_a_id,
        user_b_id,
        distance_meters,
        geohash_match,
        status,
        created_at,
        expires_at
    ) VALUES (
        LEAST(signal1_id::text, signal2_id::text)::uuid,
        GREATEST(signal1_id::text, signal2_id::text)::uuid,
        LEAST(user1_id::text, user2_id::text)::uuid,
        GREATEST(user1_id::text, user2_id::text)::uuid,
        15,  -- 15 meters apart
        '9q8yyk',
        'pending',
        NOW(),
        NOW() + INTERVAL '30 seconds'
    ) RETURNING id INTO mutual_signal_id;
    
    RAISE NOTICE 'Mutual signal created: %', mutual_signal_id;
    
    -- ==============================================
    -- CREATE REVEAL
    -- ==============================================
    
    RAISE NOTICE 'Creating reveal...';
    
    INSERT INTO reveals (
        mutual_signal_id,
        viewer_id,
        viewed_id,
        created_at,
        expires_at,
        last_viewed_at,
        view_count
    ) VALUES (
        mutual_signal_id,
        user1_id,
        user2_id,
        NOW(),
        NOW() + INTERVAL '15 minutes',
        NOW(),
        1
    ) RETURNING id INTO reveal_id;
    
    INSERT INTO reveals (
        mutual_signal_id,
        viewer_id,
        viewed_id,
        created_at,
        expires_at
    ) VALUES (
        mutual_signal_id,
        user2_id,
        user1_id,
        NOW(),
        NOW() + INTERVAL '15 minutes'
    );
    
    RAISE NOTICE 'Reveal created: %', reveal_id;
    
    -- ==============================================
    -- CREATE INTERACTION (MESSAGE)
    -- ==============================================
    
    RAISE NOTICE 'Creating test message...';
    
    INSERT INTO interactions (
        reveal_id,
        sender_id,
        receiver_id,
        interaction_type,
        content,
        is_read,
        created_at,
        expires_at
    ) VALUES (
        reveal_id,
        user1_id,
        user2_id,
        'message',
        'Hey Sam! Nice to connect. Want to grab coffee sometime?',
        false,
        NOW(),
        NOW() + INTERVAL '10 minutes'
    );
    
    -- ==============================================
    -- CREATE SUBSCRIPTION
    -- ==============================================
    
    RAISE NOTICE 'Creating subscription...';
    
    INSERT INTO subscriptions (
        user_id,
        tier,
        provider,
        provider_subscription_id,
        daily_signal_limit,
        boost_credits_monthly,
        can_extend_reveal,
        can_see_missed_signals,
        current_period_start,
        current_period_end,
        status
    ) VALUES (
        user1_id,
        'plus',
        'stripe',
        'sub_test_123',
        30,
        10,
        false,
        true,
        NOW() - INTERVAL '15 days',
        NOW() + INTERVAL '15 days',
        'active'
    );
    
    -- ==============================================
    -- CREATE BOOST
    -- ==============================================
    
    RAISE NOTICE 'Creating boost...';
    
    INSERT INTO boosts (
        user_id,
        signal_id,
        boost_type,
        multiplier,
        new_radius_meters,
        credits_used,
        is_active,
        created_at,
        expires_at
    ) VALUES (
        user2_id,
        signal2_id,
        'range',
        1.5,
        1500,
        1,
        true,
        NOW(),
        NOW() + INTERVAL '100 seconds'
    );
    
    -- ==============================================
    -- CREATE REPORT
    -- ==============================================
    
    RAISE NOTICE 'Creating test report...';
    
    INSERT INTO reports (
        reporter_id,
        reported_user_id,
        report_type,
        description,
        status,
        device_hash,
        ip_address,
        created_at
    ) VALUES (
        user3_id,
        user1_id,
        'spam',
        'Test report for moderation system',
        'pending',
        'device-taylor-789',
        '192.168.1.100'::inet,
        NOW()
    );
    
    -- Update report score for tested user
    UPDATE users 
    SET report_score = -5 
    WHERE id = user1_id;
    
    RAISE NOTICE '================================';
    RAISE NOTICE '✅ TEST DATA CREATED SUCCESSFULLY!';
    RAISE NOTICE '================================';
    RAISE NOTICE '';
    RAISE NOTICE '🧪 TEST SCENARIOS AVAILABLE:';
    RAISE NOTICE '1. Check database has test data';
    RAISE NOTICE '2. Use these user IDs in your API tests:';
    RAISE NOTICE '   - Alex: %', user1_id;
    RAISE NOTICE '   - Sam: %', user2_id;
    RAISE NOTICE '   - Taylor: %', user3_id;
    RAISE NOTICE '3. Test match acceptance flow';
    RAISE NOTICE '4. Test messaging between users';
    RAISE NOTICE '';
    RAISE NOTICE '📊 TEST DATA CREATED:';
    RAISE NOTICE '- 3 test users';
    RAISE NOTICE '- 2 active signals';
    RAISE NOTICE '- 1 mutual signal (match)';
    RAISE NOTICE '- 2 reveals (profile access)';
    RAISE NOTICE '- 1 test message';
    RAISE NOTICE '- 1 subscription';
    RAISE NOTICE '- 1 boost';
    RAISE NOTICE '- 1 report';
    RAISE NOTICE '================================';
    
END $$;

-- Verify the data was created
SELECT 'Verification:' as check_title;

SELECT 
    (SELECT COUNT(*) FROM users WHERE display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')) as test_users,
    (SELECT COUNT(*) FROM user_presence WHERE is_online = true) as online_users,
    (SELECT COUNT(*) FROM signals WHERE status = 'active') as active_signals,
    (SELECT COUNT(*) FROM mutual_signals WHERE status = 'pending') as pending_matches,
    (SELECT COUNT(*) FROM reveals WHERE expires_at > NOW()) as active_reveals,
    (SELECT COUNT(*) FROM interactions) as total_messages;
