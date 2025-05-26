# Steam Sale Checker Job

This job checks Steam for ongoing sales and sends notifications via Telegram when sales are found.

## Features

- 🎮 Checks Steam's featured deals and special offers
- 📱 Sends notifications via Telegram with sale details
- ⏰ Runs every 6 hours automatically
- 🔒 Includes error handling and logging
- 💰 Shows discount percentages and prices

## Setup Instructions

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Send `/newbot` and follow the instructions
3. Save the bot token you receive

### 2. Get Your Chat ID

1. Start a chat with your new bot
2. Send any message to the bot
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Look for `"chat":{"id":YOUR_CHAT_ID}` in the response

### 3. Configure Environment Variables

Edit the `config.yml` file and replace the placeholder values:

```yaml
environment:
  TELEGRAM_BOT_TOKEN: "1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"  # Your bot token
  TELEGRAM_CHAT_ID: "123456789"  # Your chat ID (can be negative for groups)
  STEAM_WISHLIST_URL: "https://store.steampowered.com/wishlist/profiles/your_steam_id/wishlistdata/"  # Optional
```

### 4. Test the Job

You can test the job manually:

```bash
# Navigate to the job directory
cd example_jobs/steam_sale_checker

# Set environment variables temporarily
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"

# Run the job
ruby execute.rb
```

## Configuration Options

### Schedule Frequency

You can modify the check frequency in `config.yml`:

```yaml
# Every hour
schedule: "0 * * * *"

# Every 3 hours
schedule: "0 */3 * * *"

# Every 12 hours
schedule: "0 */12 * * *"

# Daily at 9 AM
schedule: "0 9 * * *"
```

### Timeout

Adjust the timeout if needed:

```yaml
timeout: 120  # 2 minutes (recommended)
timeout: 60   # 1 minute (faster)
timeout: 300  # 5 minutes (more patient)
```

## What Gets Checked

The job monitors:

1. **Featured Deals** - Steam's main featured games on sale
2. **Special Offers** - Steam's special promotion section

## Notification Format

When sales are found, you'll receive messages like:

```
🎮 Steam Sales Alert!

15 games currently on sale!

• Game Name 1 (75% off)
• Game Name 2 (50% off)
• Game Name 3 (25% off)

🔗 Check more at: https://store.steampowered.com/
```

## Troubleshooting

### Common Issues

1. **No notifications received**
   - Verify bot token and chat ID are correct
   - Make sure you've started a conversation with the bot
   - Check the job logs for errors

2. **Job times out**
   - Steam API might be slow
   - Increase timeout in config.yml
   - Check your internet connection

3. **Error messages**
   - The job will send error notifications to Telegram
   - Check scheduler logs for detailed error information

### Testing Connection

Test your Telegram setup:

```bash
# Quick test (replace with your values)
curl -X POST "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/sendMessage" \
     -H "Content-Type: application/json" \
     -d '{"chat_id": "<YOUR_CHAT_ID>", "text": "Test message from Steam checker!"}'
```

## Extending the Job

You can enhance this job by:

- Adding Steam wishlist monitoring (using STEAM_WISHLIST_URL)
- Filtering for specific games or genres
- Adding price threshold notifications
- Integrating with other notification services (Discord, Slack, etc.)
- Storing sale history to avoid duplicate notifications

## Rate Limiting

The job is designed to be respectful of Steam's API:
- Only checks public endpoints
- Includes reasonable timeouts
- Runs every 6 hours by default
- Has built-in delays between requests