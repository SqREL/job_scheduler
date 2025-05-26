#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

# Configuration from environment variables
TELEGRAM_BOT_TOKEN = ENV['TELEGRAM_BOT_TOKEN']
TELEGRAM_CHAT_ID = ENV['TELEGRAM_CHAT_ID']
STEAM_WISHLIST_URL = ENV['STEAM_WISHLIST_URL']

def log(message)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{message}"
end

def send_telegram_message(message)
  return false if TELEGRAM_BOT_TOKEN.nil? || TELEGRAM_BOT_TOKEN.empty?
  
  uri = URI("https://api.telegram.org/bot#{TELEGRAM_BOT_TOKEN}/sendMessage")
  
  params = {
    chat_id: TELEGRAM_CHAT_ID,
    text: message,
    parse_mode: 'HTML'
  }
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = params.to_json
  
  response = http.request(request)
  response.code == '200'
rescue => e
  log("Failed to send Telegram message: #{e.message}")
  false
end

def check_steam_featured_sales
  # Check Steam's featured sales page
  uri = URI('https://store.steampowered.com/api/featured/')
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 30
  
  response = http.get(uri.path)
  
  if response.code == '200'
    data = JSON.parse(response.body)
    
    # Check if there are featured deals
    if data['featured_win'] && data['featured_win'].any?
      featured_count = data['featured_win'].length
      log("Found #{featured_count} featured games on sale")
      
      # Get some example games
      examples = data['featured_win'].first(3).map do |game|
        name = game['name'] || 'Unknown Game'
        discount = game['discount_percent'] || 0
        "• #{name} (#{discount}% off)"
      end
      
      return {
        has_sales: true,
        message: "🎮 <b>Steam Sales Alert!</b>\n\n#{featured_count} games currently on sale!\n\n#{examples.join("\n")}\n\n🔗 Check more at: https://store.steampowered.com/"
      }
    end
  else
    log("Failed to fetch Steam API: HTTP #{response.code}")
  end
  
  return { has_sales: false, message: nil }
rescue => e
  log("Error checking Steam sales: #{e.message}")
  return { has_sales: false, message: nil }
end

def check_steam_specials
  # Check Steam's specials page API
  uri = URI('https://store.steampowered.com/api/featuredcategories/')
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 30
  
  response = http.get(uri.path)
  
  if response.code == '200'
    data = JSON.parse(response.body)
    
    # Check specials section
    if data['specials'] && data['specials']['items'] && data['specials']['items'].any?
      specials_count = data['specials']['items'].length
      log("Found #{specials_count} special offers")
      
      # Get some example games from specials
      examples = data['specials']['items'].first(3).map do |game|
        name = game['name'] || 'Unknown Game'
        discount = game['discount_percent'] || 0
        original_price = (game['original_price'].to_f / 100).round(2) if game['original_price']
        final_price = (game['final_price'].to_f / 100).round(2) if game['final_price']
        
        price_info = if original_price && final_price && original_price != final_price
          " ($#{final_price}, was $#{original_price})"
        elsif final_price
          " ($#{final_price})"
        else
          ""
        end
        
        "• #{name} (#{discount}% off)#{price_info}"
      end
      
      return {
        has_sales: true,
        message: "🔥 <b>Steam Special Offers!</b>\n\n#{specials_count} special deals available!\n\n#{examples.join("\n")}\n\n🔗 View all specials: https://store.steampowered.com/specials/"
      }
    end
  else
    log("Failed to fetch Steam specials API: HTTP #{response.code}")
  end
  
  return { has_sales: false, message: nil }
rescue => e
  log("Error checking Steam specials: #{e.message}")
  return { has_sales: false, message: nil }
end

# Main execution
begin
  log("Starting Steam sale checker...")
  
  # Validate required environment variables
  if TELEGRAM_BOT_TOKEN.nil? || TELEGRAM_BOT_TOKEN.empty?
    log("ERROR: TELEGRAM_BOT_TOKEN not set")
    exit 1
  end
  
  if TELEGRAM_CHAT_ID.nil? || TELEGRAM_CHAT_ID.empty?
    log("ERROR: TELEGRAM_CHAT_ID not set")
    exit 1
  end
  
  log("Checking Steam for sales...")
  
  # Check both featured and specials
  featured_result = check_steam_featured_sales
  specials_result = check_steam_specials
  
  # Determine what to send
  messages_to_send = []
  
  if featured_result[:has_sales]
    messages_to_send << featured_result[:message]
  end
  
  if specials_result[:has_sales]
    messages_to_send << specials_result[:message]
  end
  
  if messages_to_send.any?
    log("Sales found! Sending notifications...")
    
    messages_to_send.each do |message|
      if send_telegram_message(message)
        log("Telegram notification sent successfully")
      else
        log("Failed to send Telegram notification")
      end
      
      # Small delay between messages
      sleep(1) if messages_to_send.length > 1
    end
    
    log("Steam sale check completed - sales found and notifications sent")
  else
    log("No significant sales found at this time")
    
    # Optionally send a "no sales" message (uncomment if desired)
    # send_telegram_message("🎮 Steam Check: No major sales at the moment. Will check again in 6 hours!")
  end
  
  exit 0
  
rescue => e
  error_message = "❌ <b>Steam Sale Checker Error</b>\n\nFailed to check Steam sales: #{e.message}"
  log("FATAL ERROR: #{e.message}")
  
  # Try to send error notification
  send_telegram_message(error_message)
  
  exit 1
end