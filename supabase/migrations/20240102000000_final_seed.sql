-- FINAL TEST DATA SEED (Without trigger issues)

-- First, temporarily disable the problematic trigger
DROP TRIGGER IF EXISTS trigger_find_matches ON signals;

-- Clear existing test data
DO $$ 
BEGIN
    RAISE NOTICE 'Cleaning up old test data...';
    
    -- Get test user IDs
    WITH test_users AS (
        SELECT id FROM users 
        WHERE display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm', 'Test User A', 'Test User B')
    )
    -- Delete in correct order
    DELETE FROM reports WHERE reporter_id IN (SELECT id FROM test_users);
    DELETE FROM boosts WHERE user_id IN (SELECT id FROM test_users);
    DELETE FROM subscriptions WHERE user_id IN (SELECT id FROM test_users);
    DELETE FROM interactions WHERE sender_id IN (SELECT id FROM test_users) OR receiver_id IN (SELECT id FROM test_users);
    DELETE FROM reveals WHERE viewer_id IN (SELECT id FROM test_users) OR viewed_id IN (SELECT id FROM test_users);
    DELETE FROM mutual_signals WHERE user_a_id IN (SELECT id FROM test_users) OR user_b_id IN (SELECT id FROM test_users);
    DELETE FROM signals WHERE user_id IN (SELECT id FROM test_users);
    DELETE FROM user_presence WHERE user_id IN (SELECT id FROM test_users);
    
    -- Delete the users
    DELETE FROM users WHERE display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm', 'Test User A', 'Test User B');
    
    RAISE NOTICE 'Cleanup complete!';
END $$;

-- ==============================================
-- CREATE TEST USERS (SIMPLE VERSION)
-- ==============================================

DO $$
DECLARE
    user1_id UUID;
    user2_id UUID;
    user3_id UUID;
    signal1_id UUID;
    signal2_id UUID;
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
        subscription_tier
    ) VALUES (
        gen_random_uuid(),
        'Alex Johnson',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=Alex',
        'Digital nomad exploring coffee shops. Love tech and travel!',
        1500,
        'balanced',
        'plus'
    ) RETURNING id INTO user1_id;
    
    -- User 2: Sam CoffeeLover
    INSERT INTO users (
        auth_id,
        display_name,
        avatar_url,
        short_bio,
        max_distance_meters,
        visibility_preference,
        subscription_tier
    ) VALUES (
        gen_random_uuid(),
        'Sam CoffeeLover',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=Sam',
        'Barista by day, gamer by night. Always up for coffee chat!',
        1000,
        'visible',
        'free'
    ) RETURNING id INTO user2_id;
    
    -- User 3: Taylor Bookworm
    INSERT INTO users (
        auth_id,
        display_name,
        avatar_url,
        short_bio,
        max_distance_meters,
        visibility_preference,
        subscription_tier,
        report_score
    ) VALUES (
        gen_random_uuid(),
        'Taylor Bookworm',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=Taylor',
        'Reading at the park. Love sci-fi and fantasy novels!',
        800,
        'discreet',
        'premium',
        -5
    ) RETURNING id INTO user3_id;
    
    RAISE NOTICE '✅ Users created with IDs:';
    RAISE NOTICE '   Alex: %', user1_id;
    RAISE NOTICE '   Sam: %', user2_id;
    RAISE NOTICE '   Taylor: %', user3_id;
    
    -- ==============================================
    -- CREATE PRESENCE
    -- ==============================================
    
    RAISE NOTICE 'Creating presence records...';
    
    INSERT INTO user_presence (user_id, geohash, lat, lng, device_hash, is_online, expires_at)
    VALUES 
        (user1_id, '9q8yyk', 37.7749, -122.4194, 'device-alex', true, NOW() + INTERVAL '5 minutes'),
        (user2_id, '9q8yyk', 37.7749, -122.4194, 'device-sam', true, NOW() + INTERVAL '5 minutes'),
        (user3_id, '9q8yym', 37.7752, -122.4189, 'device-taylor', true, NOW() + INTERVAL '3 minutes');
    
    RAISE NOTICE '✅ Presence records created';
    
    -- ==============================================
    -- CREATE SIGNALS (Without triggering distance calculation)
    -- ==============================================
    
    RAISE NOTICE 'Creating signals...';
    
    -- Signal for Alex
    INSERT INTO signals (
        user_id,
        geohash,
        lat,
        lng,
        signal_type,
        visibility_radius_meters,
        status,
        expires_at
    ) VALUES (
        user1_id,
        '9q8yyk',
        37.7749,
        -122.4194,
        'standard',
        1000,
        'active',
        NOW() + INTERVAL '2 minutes'
    ) RETURNING id INTO signal1_id;
    
    -- Signal for Sam
    INSERT INTO signals (
        user_id,
        geohash,
        lat,
        lng,
        signal_type,
        visibility_radius_meters,
        status,
        expires_at
    ) VALUES (
        user2_id,
        '9q8yyk',
        37.7749,
        -122.4194,
        'boosted',
        1500,
        'active',
        NOW() + INTERVAL '2 minutes'
    ) RETURNING id INTO signal2_id;
    
    RAISE NOTICE '✅ Signals created: % and %', signal1_id, signal2_id;
    
    -- ==============================================
    -- CREATE MANUAL MATCH (Simulate what trigger would do)
    -- ==============================================
    
    RAISE NOTICE 'Creating match...';
    
    INSERT INTO mutual_signals (
        signal_a_id,
        signal_b_id,
        user_a_id,
        user_b_id,
        distance_meters,
        geohash_match,
        status,
        expires_at
    ) VALUES (
        signal1_id,
        signal2_id,
        user1_id,
        user2_id,
        15,
        '9q8yyk',
        'pending',
        NOW() + INTERVAL '30 seconds'
    );
    
    RAISE NOTICE '✅ Match created between Alex and Sam';
    
    -- ==============================================
    -- CREATE A FEW MORE TEST RECORDS
    -- ==============================================
    
    -- Create a subscription for Alex
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
        'sub_alex_123',
        30,
        10,
        true,
        true,
        NOW() - INTERVAL '10 days',
        NOW() + INTERVAL '20 days',
        'active'
    );
    
    -- Create a boost for Sam's signal
    INSERT INTO boosts (
        user_id,
        signal_id,
        boost_type,
        multiplier,
        new_radius_meters,
        credits_used,
        is_active,
        expires_at
    ) VALUES (
        user2_id,
        signal2_id,
        'range',
        1.5,
        1500,
        1,
        true,
        NOW() + INTERVAL '100 seconds'
    );
    
    -- Create a test report
    INSERT INTO reports (
        reporter_id,
        reported_user_id,
        report_type,
        description,
        status,
        device_hash,
        ip_address
    ) VALUES (
        user3_id,
        user1_id,
        'spam',
        'Test report for API testing',
        'pending',
        'device-taylor',
        '192.168.1.100'::inet
    );
    
    RAISE NOTICE '✅ Additional test data created';
    
    -- ==============================================
    -- SUMMARY
    -- ==============================================
    
    RAISE NOTICE '';
    RAISE NOTICE '🎉 TEST DATA SEEDED SUCCESSFULLY!';
    RAISE NOTICE '================================';
    RAISE NOTICE '📱 Test Users Created:';
    RAISE NOTICE '   1. Alex Johnson (Plus subscriber)';
    RAISE NOTICE '   2. Sam CoffeeLover (Free user, has boost)';
    RAISE NOTICE '   3. Taylor Bookworm (Premium, reported Alex)';
    RAISE NOTICE '';
    RAISE NOTICE '📍 Location Data:';
    RAISE NOTICE '   - Alex & Sam: Same location (should match)';
    RAISE NOTICE '   - Taylor: Nearby location';
    RAISE NOTICE '';
    RAISE NOTICE '🤝 Match Status:';
    RAISE NOTICE '   - Alex ↔ Sam: PENDING match';
    RAISE NOTICE '   - Both need to accept to reveal profiles';
    RAISE NOTICE '';
    RAISE NOTICE '🔧 Ready for API Testing!';
    
END $$;

-- Re-enable the trigger
CREATE TRIGGER trigger_find_matches
    AFTER INSERT ON signals
    FOR EACH ROW
    EXECUTE FUNCTION find_signal_matches();

-- Verify the data
SELECT '✅ Verification Check:' as title;

SELECT 'Users:' as table_name, COUNT(*) as count FROM users
UNION ALL
SELECT 'Online Presence:', COUNT(*) FROM user_presence WHERE is_online = true
UNION ALL
SELECT 'Active Signals:', COUNT(*) FROM signals WHERE status = 'active'
UNION ALL
SELECT 'Pending Matches:', COUNT(*) FROM mutual_signals WHERE status = 'pending'
UNION ALL
SELECT 'Subscriptions:', COUNT(*) FROM subscriptions
UNION ALL
SELECT 'Active Boosts:', COUNT(*) FROM boosts WHERE is_active = true
UNION ALL
SELECT 'Pending Reports:', COUNT(*) FROM reports WHERE status = 'pending';

-- Show test user details
SELECT 'Test User Details:' as details;
SELECT 
    display_name,
    subscription_tier as tier,
    report_score,
    created_at
FROM users 
WHERE display_name IN ('Alex Johnson', 'Sam CoffeeLover', 'Taylor Bookworm')
ORDER BY created_at;
