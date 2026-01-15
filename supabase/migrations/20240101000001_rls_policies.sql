-- ==============================================
-- ROW LEVEL SECURITY POLICIES
-- ==============================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE mutual_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE reveals ENABLE ROW LEVEL SECURITY;
ALTER TABLE interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE boosts ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

-- USERS
CREATE POLICY users_select_self ON users
    FOR SELECT USING (auth.uid() = auth_id);
CREATE POLICY users_update_self ON users
    FOR UPDATE USING (auth.uid() = auth_id);
CREATE POLICY users_insert_auth ON users
    FOR INSERT WITH CHECK (auth.uid() = auth_id);

-- USER_PRESENCE
CREATE POLICY presence_select_self ON user_presence
    FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));
CREATE POLICY presence_upsert_self ON user_presence
    FOR ALL USING (user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));

-- SIGNALS
CREATE POLICY signals_select_self ON signals
    FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));
CREATE POLICY signals_insert_self ON signals
    FOR INSERT WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));
CREATE POLICY signals_update_self ON signals
    FOR UPDATE USING (user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) AND status = 'active');

-- MUTUAL_SIGNALS
CREATE POLICY mutual_signals_select_participant ON mutual_signals
    FOR SELECT USING (
        user_a_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) OR
        user_b_id IN (SELECT id FROM users WHERE auth_id = auth.uid())
    );
CREATE POLICY mutual_signals_update_own ON mutual_signals
    FOR UPDATE USING (
        (user_a_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) AND NOT user_a_declined) OR
        (user_b_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) AND NOT user_b_declined)
    );

-- REVEALS
CREATE POLICY reveals_select_participant ON reveals
    FOR SELECT USING (
        viewer_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) OR
        viewed_id IN (SELECT id FROM users WHERE auth_id = auth.uid())
    );
CREATE POLICY reveals_update_viewer ON reveals
    FOR UPDATE USING (viewer_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));

-- INTERACTIONS
CREATE POLICY interactions_select_participant ON interactions
    FOR SELECT USING (
        sender_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) OR
        receiver_id IN (SELECT id FROM users WHERE auth_id = auth.uid())
    );
CREATE POLICY interactions_insert_sender ON interactions
    FOR INSERT WITH CHECK (
        sender_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) AND
        EXISTS (
            SELECT 1 FROM reveals r 
            WHERE r.id = reveal_id 
            AND r.viewer_id = sender_id 
            AND r.viewed_id = receiver_id
            AND r.expires_at > NOW()
        )
    );

-- SUBSCRIPTIONS
CREATE POLICY subscriptions_select_self ON subscriptions
    FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));

-- BOOSTS
CREATE POLICY boosts_select_self ON boosts
    FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));
CREATE POLICY boosts_insert_self ON boosts
    FOR INSERT WITH CHECK (
        user_id IN (SELECT id FROM users WHERE auth_id = auth.uid()) AND
        EXISTS (
            SELECT 1 FROM signals s 
            WHERE s.id = signal_id 
            AND s.user_id = user_id 
            AND s.status = 'active'
        )
    );

-- REPORTS
CREATE POLICY reports_insert_any ON reports
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY reports_select_own ON reports
    FOR SELECT USING (reporter_id IN (SELECT id FROM users WHERE auth_id = auth.uid()));
