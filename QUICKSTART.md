# Nutrition AI Assistant - Quick Start Guide

## 🚀 Run the AI Assistant NOW!

### Option 1: Quick Start (Demo Mode)

Run without API key to test the UI with simulated responses:

```powershell
# Switch to AI mode
Move-Item lib\main.dart lib\main_json_backup.dart -Force -ErrorAction SilentlyContinue
Copy-Item lib\main_ai.dart lib\main.dart -Force

# Run the app
flutter run
```

The app will work in demo mode with realistic sample data!

### Option 2: Full AI Mode (Recommended)

Get real AI analysis in 2 minutes:

1. **Get FREE API Key**:
   - Open: https://makersuite.google.com/app/apikey
   - Sign in with Google
   - Click "Create API Key"
   - Copy the key

2. **Add to App**:
   - Open: `lib\main_ai.dart`
   - Find line 109: `const apiKey = 'YOUR_GEMINI_API_KEY_HERE';`
   - Replace with: `const apiKey = 'YOUR_ACTUAL_KEY';`
   - Save file

3. **Activate & Run**:
   ```powershell
   Move-Item lib\main.dart lib\main_json_backup.dart -Force -ErrorAction SilentlyContinue
   Copy-Item lib\main_ai.dart lib\main.dart -Force
   flutter run
   ```

## 📸 How to Use

1. **Tap "Camera"** to take a photo of food
   - Or **"Gallery"** to upload existing image
2. **Tap "Analyze Food"** floating button
3. **Read AI recommendation** and compliance score
4. **Tap "Add to Log"** if it fits your goals!

## 🎯 What You Get

- ✅ **Product name** & serving size
- ✅ **Full nutrition breakdown** (calories, protein, carbs, fat, sugar)
- ✅ **Smart recommendation** (should you eat it?)
- ✅ **Compliance score** (0-100 how well it fits)
- ✅ **Personalized tips** for consuming the product
- ✅ **Healthier alternatives** if not recommended
- ✅ **Ingredient analysis** & allergen warnings

## 🔄 Switch Back to JSON Mode

To return to the original evaluation engine:

```powershell
Move-Item lib\main.dart lib\main_ai_backup.dart -Force
Move-Item lib\main_json_backup.dart lib\main.dart -Force
flutter run
```

## 📱 Test with These Products

Try scanning:

- Protein bars
- Cereal boxes
- Yogurt containers
- Packaged snacks
- Nutrition labels on any food

## 💡 Pro Tips

- 📷 Ensure good lighting for better accuracy
- 🎯 Focus on the nutrition facts label
- 🔄 Try multiple products to see different recommendations
- 📊 Check your daily progress dashboard at the top
- ⚙️ Customize your daily goals in the code

## ⚡ Keyboard Shortcuts (when app running)

- `r` - Hot reload (apply code changes)
- `R` - Hot restart (reset app state)
- `q` - Quit app

---

**Ready? Run the commands above and start scanning food! 🚀**
