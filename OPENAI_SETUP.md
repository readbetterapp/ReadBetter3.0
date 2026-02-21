# OpenAI API Setup Guide

## Setting the API Key

The Daily Inspiration feature uses OpenAI's API to generate book-related quotes. To enable this feature, you need to set your OpenAI API key as an environment variable.

### Option 1: Xcode Scheme Environment Variable (Recommended for Development)

1. In Xcode, select your target scheme (top bar, next to the device selector)
2. Click "Edit Scheme..."
3. Select "Run" from the left sidebar
4. Go to the "Arguments" tab
5. Under "Environment Variables", click the "+" button
6. Add:
   - **Name:** `OPENAI_API_KEY`
   - **Value:** Your OpenAI API key (starts with `sk-`)

### Option 2: Launch Arguments (Alternative)

You can also pass it via launch arguments in the scheme settings.

### Option 3: Hardcode for Testing (Not Recommended for Production)

In `HomeView.swift`, temporarily replace:
```swift
@StateObject private var quoteService = QuoteService(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
```

With:
```swift
@StateObject private var quoteService = QuoteService(apiKey: "sk-your-api-key-here")
```

**⚠️ Never commit hardcoded API keys to version control!**

## How to Get an OpenAI API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Sign up or log in
3. Navigate to API Keys section
4. Create a new API key
5. Copy the key (starts with `sk-`)

## Cost Considerations

- The app uses **GPT-3.5-turbo** model (cheapest option)
- Quotes are **cached for 24 hours** per device
- Uses a **daily seed** so all users get the same quote (reduces API calls)
- Each quote generation costs approximately **$0.0001-0.0002**
- With proper caching, you'll make only **1 API call per day** (when the first user opens the app)

## Verifying the API is Working

The app now includes console logging to help you verify:

1. Open Xcode Console (⌘+Shift+Y)
2. Launch the app
3. Look for these log messages:

### Success:
```
🔄 QuoteService: Fetching new quote from OpenAI...
✅ QuoteService: Successfully fetched and cached quote
```

### Using Cache:
```
📖 QuoteService: Using cached quote from today
```

### Errors:
```
❌ QuoteService: No API key configured
```
or
```
❌ QuoteService: Failed to fetch quote - [error message]
```

## What Changed from Original Implementation

### Before:
- Had 8 fallback quotes that would be used if API failed
- Random quote selection
- No way to tell if API was working

### After:
- **No fallback quotes** - will show error if API fails
- **Daily seed** ensures all users see the same quote on the same day
- **Console logging** shows exactly what's happening
- **Error UI** displays in the app when API key is missing or API fails
- **Temperature set to 0.0** for deterministic output

## Troubleshooting

### "OpenAI API key not configured" error
- The environment variable `OPENAI_API_KEY` is not set
- Check your Xcode scheme settings

### "API error with status code: 401"
- Your API key is invalid or expired
- Get a new key from OpenAI platform

### "API error with status code: 429"
- Rate limit exceeded or insufficient credits
- Check your OpenAI account billing

### Quote doesn't change daily
- This is expected! The same quote should show for all users on the same day
- Clear the app's UserDefaults or wait until tomorrow to see a new quote

## Testing Different Quotes

To test and see different quotes without waiting:

1. Clear cached quote:
```swift
UserDefaults.standard.removeObject(forKey: "cached_daily_quote")
UserDefaults.standard.removeObject(forKey: "cached_quote_date")
UserDefaults.standard.removeObject(forKey: "cached_quote_author")
```

2. Or modify the `getDailySeed()` function temporarily to return a different value



