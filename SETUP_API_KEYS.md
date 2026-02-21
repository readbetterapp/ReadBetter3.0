# API Keys Setup Guide

## ✅ What I Just Did

1. Created `Secrets.xcconfig` - stores your API keys
2. Created `Config.swift` - provides clean access to config values
3. Updated `HomeView.swift` - now uses `Config.openAIAPIKey`
4. Added `Secrets.xcconfig` to `.gitignore` - keeps keys out of git

## 🔧 Next Steps (You Need to Do These in Xcode)

### Step 1: Add Your OpenAI API Key

Edit `Secrets.xcconfig` and replace the placeholder with your actual key:

```
OPENAI_API_KEY = sk-proj-your-actual-key-here
```

### Step 2: Configure Xcode Project

1. **Open your project in Xcode**
2. **Select your project** in the navigator (top-level "ReadBetterApp3.0")
3. **Select your app target** (ReadBetterApp3.0)
4. Go to **Build Settings** tab
5. Search for "**Info.plist**"
6. Find "**Info.plist Values**" section
7. Click the **+** button to add a new key
8. Set:
   - **Key:** `OPENAI_API_KEY`
   - **Value:** `$(OPENAI_API_KEY)`

### Step 3: Link the xcconfig File

1. **Select your project** (not target) in the navigator
2. Go to the **Info** tab
3. Under **Configurations**, you'll see Debug and Release
4. For **both Debug and Release**:
   - Click the dropdown under your target name
   - Select **Secrets** (or click "+" to add the Secrets.xcconfig file if not listed)

### Step 4: Verify It Works

**For Local Development:**
- Your Xcode scheme environment variable still works (if set)
- Falls back to xcconfig if not set

**For TestFlight/Release:**
- Automatically uses the key from Secrets.xcconfig
- No more "API key not configured" errors!

## 📝 How It Works

```
Secrets.xcconfig
    ↓
Info.plist (via build settings)
    ↓
Config.swift (reads from Info.plist)
    ↓
HomeView.swift (uses Config.openAIAPIKey)
```

## 🔒 Security Notes

- ✅ `Secrets.xcconfig` is in `.gitignore` - won't be committed
- ✅ Works in all build configurations (Debug, Release, TestFlight, App Store)
- ✅ Easy to update - just edit one file
- ⚠️ Still embedded in the app binary (can be extracted by determined attackers)
- 💡 For maximum security, consider using a backend API to proxy OpenAI calls

## 🐛 Troubleshooting

**"No OpenAI API key found" in logs:**
- Check that Secrets.xcconfig has the correct key
- Verify Info.plist has `OPENAI_API_KEY` = `$(OPENAI_API_KEY)`
- Clean build folder (Cmd+Shift+K) and rebuild

**Still not working in TestFlight:**
- Make sure you set the xcconfig for **Release** configuration
- Archive again after making changes

**Key shows as literal "$(OPENAI_API_KEY)":**
- The xcconfig file isn't linked properly
- Go back to Step 3 and ensure it's set for your configuration



