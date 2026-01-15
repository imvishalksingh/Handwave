#!/bin/bash

# Digital Hand Signal Backend Deployment Script
set -e

echo "🚀 Starting deployment process..."

# Check for required environment variables
if [ -z "$APP_SUPABASE_URL" ] || [ -z "$APP_SUPABASE_SERVICE_ROLE_KEY" ]; then
  echo "❌ Missing Supabase credentials. Please set environment variables."
  exit 1
fi

# 1. Deploy database migrations
echo "📦 Deploying database migrations..."
supabase db push

# 2. Deploy Edge Functions
echo "⚡ Deploying Edge Functions..."
supabase functions deploy cleanup

# 3. Set up cron job (using external service)
echo "⏰ Setting up cleanup cron job..."
echo "=========================================="
echo "IMPORTANT: Set up a cron job to call:"
echo "URL: ${APP_SUPABASE_URL}/functions/v1/cleanup"
echo "Method: POST"
echo "Headers: Authorization: Bearer $(openssl rand -hex 32)"
echo "Schedule: */5 * * * * (Every 5 minutes)"
echo "=========================================="

# 4. Enable realtime for tables
echo "📡 Enabling realtime subscriptions..."
echo "Go to Supabase Dashboard → Replication → Tables"
echo "Enable realtime for: user_presence, signals, mutual_signals, reveals, interactions"

echo "✅ Deployment preparation complete!"
