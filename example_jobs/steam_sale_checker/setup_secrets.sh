#!/bin/bash

# Steam Sale Checker - Secrets Setup Script
# This script helps you set up the required secrets for the Steam sale checker job

echo "🔐 Steam Sale Checker - Secrets Setup"
echo "======================================"
echo

# Check if secrets binary exists
if [ ! -x "../../bin/secrets" ]; then
    echo "❌ Error: secrets binary not found at ../../bin/secrets"
    echo "Make sure you're running this from the steam_sale_checker directory"
    exit 1
fi

SECRETS_BIN="../../bin/secrets"

echo "This script will help you securely store the Telegram credentials needed"
echo "for the Steam sale checker job."
echo

# Function to read secret input
read_secret() {
    local prompt="$1"
    local var_name="$2"
    
    echo -n "$prompt: "
    read -s value
    echo
    
    if [ -z "$value" ]; then
        echo "❌ Error: $var_name cannot be empty"
        return 1
    fi
    
    if $SECRETS_BIN set "$var_name" "$value"; then
        echo "✅ $var_name stored securely"
        return 0
    else
        echo "❌ Failed to store $var_name"
        return 1
    fi
}

echo "📱 Step 1: Telegram Bot Token"
echo "If you don't have a bot token yet:"
echo "  1. Message @BotFather on Telegram"
echo "  2. Send /newbot and follow instructions"
echo "  3. Copy the token you receive"
echo

if ! read_secret "Enter your Telegram bot token" "TELEGRAM_BOT_TOKEN"; then
    exit 1
fi

echo
echo "💬 Step 2: Telegram Chat ID"
echo "To get your chat ID:"
echo "  1. Start a conversation with your bot"
echo "  2. Send any message to the bot"
echo "  3. Visit: https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
echo "  4. Look for \"chat\":{\"id\":YOUR_CHAT_ID} in the response"
echo "  5. Chat ID can be negative for group chats"
echo

if ! read_secret "Enter your Telegram chat ID" "TELEGRAM_CHAT_ID"; then
    exit 1
fi

echo
echo "🎉 Setup Complete!"
echo "=================="
echo

# Test the setup
echo "🧪 Testing Telegram connection..."

# Create a temporary test script
cat > /tmp/test_telegram.rb << 'EOF'
#!/usr/bin/env ruby
require_relative '../../lib/job_scheduler/secrets_manager'

begin
  secrets = JobSchedulerComponents::SecretsManager.new
  
  bot_token = secrets.get('TELEGRAM_BOT_TOKEN')
  chat_id = secrets.get('TELEGRAM_CHAT_ID')
  
  if bot_token.nil? || bot_token.empty?
    puts "❌ TELEGRAM_BOT_TOKEN not found in secrets"
    exit 1
  end
  
  if chat_id.nil? || chat_id.empty?
    puts "❌ TELEGRAM_CHAT_ID not found in secrets"
    exit 1
  end
  
  puts "✅ Secrets loaded successfully"
  puts "🤖 Bot token: #{bot_token[0..10]}..."
  puts "💬 Chat ID: #{chat_id}"
  
  # Test actual Telegram API
  require 'net/http'
  require 'json'
  require 'uri'
  
  uri = URI("https://api.telegram.org/bot#{bot_token}/sendMessage")
  
  params = {
    chat_id: chat_id,
    text: "🎮 Steam Sale Checker setup complete! Your bot is ready to notify you about Steam sales."
  }
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = params.to_json
  
  response = http.request(request)
  
  if response.code == '200'
    puts "✅ Test message sent successfully to Telegram!"
    puts "Check your Telegram chat for a confirmation message."
  else
    puts "❌ Failed to send test message: HTTP #{response.code}"
    puts "Response: #{response.body}"
    exit 1
  end
  
rescue => e
  puts "❌ Test failed: #{e.message}"
  exit 1
end
EOF

# Run the test
if ruby /tmp/test_telegram.rb; then
    echo
    echo "🎯 Your Steam sale checker is ready!"
    echo
    echo "Next steps:"
    echo "1. Add this job directory to your jobs Git repository"
    echo "2. The scheduler will automatically pick it up"
    echo "3. You'll receive notifications every 6 hours when Steam sales are found"
    echo
    echo "To check stored secrets: $SECRETS_BIN list"
    echo "To view a secret (masked): $SECRETS_BIN get TELEGRAM_BOT_TOKEN"
else
    echo
    echo "❌ Setup test failed. Please check your bot token and chat ID."
    echo "You can re-run this script to try again."
fi

# Clean up
rm -f /tmp/test_telegram.rb