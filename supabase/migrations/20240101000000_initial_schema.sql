-- ==============================================
-- COMPLETE DATABASE SCHEMA
-- ==============================================

----------------------------------------------
-- USERS (Minimal anonymous profile)
----------------------------------------------
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id UUID UNIQUE NOT NULL,
    display_name VARCHAR(32) NOT NULL,
    avatar_url TEXT,
    short_bio TEXT CHECK (char_length(short_bio) <= 100),
    max_distance_meters INTEGER DEFAULT 1000,
    visibility_preference VARCHAR(20) DEFAULT 'balanced' CHECK (visibility_preference IN ('discreet', 'balanced', 'visible')),
    signals_today INTEGER DEFAULT 0,
    last_signal_at TIMESTAMPTZ,
    report_score INTEGER DEFAULT 0,
    subscription_tier VARCHAR(20) DEFAULT 'free' CHECK (subscription_tier IN ('free', 'plus', 'premium')),
    subscription_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT display_name_length CHECK (char_length(display_name) >= 2 AND char_length(display_name) <= 32)
);

----------------------------------------------
-- USER_PRESENCE (Live location with TTL)
----------------------------------------------
CREATE TABLE user_presence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    geohash VARCHAR(12) NOT NULL,
    lat DECIMAL(9,6) NOT NULL,
    lng DECIMAL(9,6) NOT NULL,
    device_hash VARCHAR(64),
    is_online BOOLEAN DEFAULT true,
    last_ping_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '90 seconds',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT geohash_length CHECK (char_length(geohash) BETWEEN 6 AND 8)
);

----------------------------------------------
-- SIGNALS (Temporary "I'm Open" signals)
----------------------------------------------
CREATE TABLE signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    geohash VARCHAR(12) NOT NULL,
    lat DECIMAL(9,6) NOT NULL,
    lng DECIMAL(9,6) NOT NULL,
    signal_type VARCHAR(20) DEFAULT 'standard' CHECK (signal_type IN ('standard', 'boosted')),
    visibility_radius_meters INTEGER DEFAULT 1000,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'matched', 'expired', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '120 seconds',
    boost_id UUID,
    CONSTRAINT signal_duration CHECK (expires_at <= created_at + INTERVAL '300 seconds')
);

----------------------------------------------
-- MUTUAL_SIGNALS (Overlap detection)
----------------------------------------------
CREATE TABLE mutual_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    signal_a_id UUID REFERENCES signals(id) ON DELETE CASCADE,
    signal_b_id UUID REFERENCES signals(id) ON DELETE CASCADE,
    user_a_id UUID REFERENCES users(id) ON DELETE CASCADE,
    user_b_id UUID REFERENCES users(id) ON DELETE CASCADE,
    distance_meters INTEGER,
    geohash_match VARCHAR(12),
    user_a_acknowledged BOOLEAN DEFAULT false,
    user_b_acknowledged BOOLEAN DEFAULT false,
    user_a_declined BOOLEAN DEFAULT false,
    user_b_declined BOOLEAN DEFAULT false,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '30 seconds',
    CONSTRAINT unique_signal_pair UNIQUE(signal_a_id, signal_b_id),
    CONSTRAINT valid_pair CHECK (signal_a_id != signal_b_id AND user_a_id != user_b_id),
    CONSTRAINT cannot_ack_and_decline CHECK (
        NOT (user_a_acknowledged = true AND user_a_declined = true) AND
        NOT (user_b_acknowledged = true AND user_b_declined = true)
    )
);

----------------------------------------------
-- REVEALS (Temporary profile access)
----------------------------------------------
CREATE TABLE reveals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mutual_signal_id UUID REFERENCES mutual_signals(id) ON DELETE CASCADE,
    viewer_id UUID REFERENCES users(id) ON DELETE CASCADE,
    viewed_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '15 minutes',
    last_viewed_at TIMESTAMPTZ DEFAULT NOW(),
    view_count INTEGER DEFAULT 1,
    CONSTRAINT unique_reveal_pair UNIQUE(mutual_signal_id, viewer_id, viewed_id)
);

----------------------------------------------
-- INTERACTIONS (One-time messages)
----------------------------------------------
CREATE TABLE interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reveal_id UUID REFERENCES reveals(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    interaction_type VARCHAR(20) CHECK (interaction_type IN ('message', 'contact_request', 'contact_share')),
    content TEXT CHECK (char_length(content) <= 500),
    contact_data JSONB,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '10 minutes',
    CONSTRAINT content_or_contact CHECK (
        (interaction_type = 'message' AND content IS NOT NULL) OR
        (interaction_type IN ('contact_request', 'contact_share') AND contact_data IS NOT NULL)
    )
);

----------------------------------------------
-- SUBSCRIPTIONS
----------------------------------------------
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    tier VARCHAR(20) NOT NULL CHECK (tier IN ('plus', 'premium')),
    provider VARCHAR(20) NOT NULL CHECK (provider IN ('app_store', 'play_store', 'stripe')),
    provider_subscription_id VARCHAR(255),
    daily_signal_limit INTEGER,
    boost_credits_monthly INTEGER,
    can_extend_reveal BOOLEAN DEFAULT false,
    can_see_missed_signals BOOLEAN DEFAULT false,
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN DEFAULT false,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'canceled', 'past_due', 'unpaid')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

----------------------------------------------
-- BOOSTS
----------------------------------------------
CREATE TABLE boosts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    signal_id UUID REFERENCES signals(id) ON DELETE CASCADE,
    boost_type VARCHAR(20) CHECK (boost_type IN ('range', 'duration', 'visibility')),
    multiplier DECIMAL(3,2) DEFAULT 1.5,
    new_radius_meters INTEGER,
    duration_extension_seconds INTEGER,
    credits_used INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

----------------------------------------------
-- REPORTS
----------------------------------------------
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    reported_signal_id UUID REFERENCES signals(id) ON DELETE SET NULL,
    reported_interaction_id UUID REFERENCES interactions(id) ON DELETE SET NULL,
    report_type VARCHAR(30) NOT NULL CHECK (report_type IN (
        'harassment', 'spam', 'fake_profile', 'inappropriate_content',
        'underage', 'offline_abuse', 'other'
    )),
    description TEXT CHECK (char_length(description) <= 500),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'dismissed')),
    moderator_notes TEXT,
    action_taken VARCHAR(50),
    device_hash VARCHAR(64),
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    CONSTRAINT must_report_something CHECK (
        reported_user_id IS NOT NULL OR
        reported_signal_id IS NOT NULL OR
        reported_interaction_id IS NOT NULL
    )
);

----------------------------------------------
-- INDEXES FOR PERFORMANCE
----------------------------------------------
CREATE INDEX idx_users_auth_id ON users(auth_id);
CREATE INDEX idx_users_report_score ON users(report_score) WHERE report_score < -5;

CREATE INDEX idx_user_presence_geohash ON user_presence(geohash);
CREATE INDEX idx_user_presence_user ON user_presence(user_id);
CREATE INDEX idx_user_presence_expires ON user_presence(expires_at) WHERE is_online = true;

CREATE INDEX idx_signals_geohash ON signals(geohash, status, expires_at);
CREATE INDEX idx_signals_user ON signals(user_id, created_at DESC);
CREATE INDEX idx_signals_expiring ON signals(expires_at) WHERE status = 'active';

CREATE INDEX idx_mutual_signals_users ON mutual_signals(user_a_id, user_b_id, status);
CREATE INDEX idx_mutual_signals_pending ON mutual_signals(status, expires_at) WHERE status = 'pending';

CREATE INDEX idx_reveals_viewer ON reveals(viewer_id, expires_at);
CREATE INDEX idx_reveals_viewed ON reveals(viewed_id, expires_at);

CREATE INDEX idx_interactions_reveal ON interactions(reveal_id, created_at DESC);
CREATE INDEX idx_interactions_participants ON interactions(sender_id, receiver_id, expires_at);

CREATE INDEX idx_subscriptions_user ON subscriptions(user_id, status, current_period_end);

CREATE INDEX idx_boosts_signal ON boosts(signal_id, is_active);
CREATE INDEX idx_boosts_user ON boosts(user_id, created_at DESC);

CREATE INDEX idx_reports_reported_user ON reports(reported_user_id, created_at DESC);
CREATE INDEX idx_reports_reporter ON reports(reporter_id, created_at DESC);
CREATE INDEX idx_reports_status ON reports(status) WHERE status = 'pending';

----------------------------------------------
-- FUNCTIONS
----------------------------------------------
-- Update user presence
CREATE OR REPLACE FUNCTION update_user_presence(
    p_user_id UUID,
    p_geohash VARCHAR,
    p_lat DECIMAL,
    p_lng DECIMAL,
    p_device_hash VARCHAR
) RETURNS UUID AS $$
DECLARE
    v_presence_id UUID;
BEGIN
    INSERT INTO user_presence (user_id, geohash, lat, lng, device_hash, last_ping_at, expires_at)
    VALUES (p_user_id, p_geohash, p_lat, p_lng, p_device_hash, NOW(), NOW() + INTERVAL '90 seconds')
    ON CONFLICT (user_id) 
    DO UPDATE SET
        geohash = EXCLUDED.geohash,
        lat = EXCLUDED.lat,
        lng = EXCLUDED.lng,
        device_hash = EXCLUDED.device_hash,
        last_ping_at = NOW(),
        expires_at = NOW() + INTERVAL '90 seconds',
        is_online = true
    RETURNING id INTO v_presence_id;
    
    RETURN v_presence_id;
END;
$$ LANGUAGE plpgsql;

-- Signal matching function
CREATE OR REPLACE FUNCTION find_signal_matches()
RETURNS TRIGGER AS $$
DECLARE
    nearby_signal RECORD;
    distance_m FLOAT;
    geohash_precision INTEGER := 6;
BEGIN
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;
    
    FOR nearby_signal IN (
        SELECT s.*, u.report_score
        FROM signals s
        JOIN users u ON s.user_id = u.id
        WHERE s.id != NEW.id
        AND s.status = 'active'
        AND s.expires_at > NOW()
        AND LEFT(s.geohash, geohash_precision) = LEFT(NEW.geohash, geohash_precision)
        AND u.report_score > -10
        AND earth_distance(
            ll_to_earth(s.lat, s.lng),
            ll_to_earth(NEW.lat, NEW.lng)
        ) <= LEAST(s.visibility_radius_meters, NEW.visibility_radius_meters)
        AND NOT EXISTS (
            SELECT 1 FROM mutual_signals ms
            WHERE (ms.signal_a_id = s.id AND ms.signal_b_id = NEW.id)
            OR (ms.signal_b_id = s.id AND ms.signal_a_id = NEW.id)
        )
        LIMIT 5
    ) LOOP
        distance_m := earth_distance(
            ll_to_earth(nearby_signal.lat, nearby_signal.lng),
            ll_to_earth(NEW.lat, NEW.lng)
        );
        
        INSERT INTO mutual_signals (
            signal_a_id,
            signal_b_id,
            user_a_id,
            user_b_id,
            distance_meters,
            geohash_match,
            expires_at
        ) VALUES (
            LEAST(NEW.id, nearby_signal.id),
            GREATEST(NEW.id, nearby_signal.id),
            LEAST(NEW.user_id, nearby_signal.user_id),
            GREATEST(NEW.user_id, nearby_signal.user_id),
            ROUND(distance_m),
            LEFT(NEW.geohash, geohash_precision),
            NOW() + INTERVAL '30 seconds'
        )
        ON CONFLICT (signal_a_id, signal_b_id) DO NOTHING;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for signal matching
CREATE TRIGGER trigger_find_matches
    AFTER INSERT ON signals
    FOR EACH ROW
    EXECUTE FUNCTION find_signal_matches();

-- Update timestamp function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
