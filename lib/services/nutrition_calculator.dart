import 'firestore_service.dart';

class NutritionCalculator {
  // Calculate Basal Metabolic Rate (BMR) using Mifflin-St Jeor Equation
  static double calculateBMR(HealthProfile profile) {
    // BMR (kcal/day)
    // Male: BMR = 10 × weight(kg) + 6.25 × height(cm) - 5 × age + 5
    // Female: BMR = 10 × weight(kg) + 6.25 × height(cm) - 5 × age - 161

    double bmr =
        (10 * profile.weight) + (6.25 * profile.height) - (5 * profile.age);

    if (profile.gender.toLowerCase() == 'male') {
      bmr += 5;
    } else if (profile.gender.toLowerCase() == 'female') {
      bmr -= 161;
    } else {
      // For 'Other', use average of male and female
      bmr -= 78; // Average of +5 and -161
    }

    return bmr;
  }

  // Calculate Total Daily Energy Expenditure (TDEE)
  // Using sedentary activity level (1.2) as default
  static double calculateTDEE(
    HealthProfile profile, {
    double activityMultiplier = 1.2,
  }) {
    // Activity multipliers:
    // 1.2 = Sedentary (little or no exercise)
    // 1.375 = Lightly active (light exercise 1-3 days/week)
    // 1.55 = Moderately active (moderate exercise 3-5 days/week)
    // 1.725 = Very active (hard exercise 6-7 days/week)
    // 1.9 = Extra active (very hard exercise, physical job)

    return calculateBMR(profile) * activityMultiplier;
  }

  // Calculate daily calorie target based on health goal
  static double calculateDailyCalories(
    HealthProfile profile,
    List<String> challenges,
  ) {
    double tdee = calculateTDEE(profile);

    // Check for weight loss or muscle gain goals
    bool hasWeightLoss = challenges.contains('weight_loss');
    bool hasMuscleGain = challenges.contains('muscle_gain');

    if (hasWeightLoss && !hasMuscleGain) {
      // Weight loss: 500 calorie deficit
      return tdee - 500;
    } else if (hasMuscleGain && !hasWeightLoss) {
      // Muscle gain: 300 calorie surplus
      return tdee + 300;
    } else {
      // Maintenance or conflicting goals
      return tdee;
    }
  }

  // Get recommended macronutrient distribution
  static Map<String, double> getRecommendedMacros(
    double dailyCalories, {
    List<String>? challenges,
  }) {
    bool hasMuscleGain = challenges?.contains('muscle_gain') ?? false;
    bool hasLowSugar = challenges?.contains('low_sugar') ?? false;

    double proteinCalories;
    double fatCalories;
    double carbCalories;

    if (hasMuscleGain) {
      // Higher protein for muscle gain: 30% protein, 25% fat, 45% carbs
      proteinCalories = dailyCalories * 0.30;
      fatCalories = dailyCalories * 0.25;
      carbCalories = dailyCalories * 0.45;
    } else if (hasLowSugar) {
      // Lower carbs for low sugar: 25% protein, 35% fat, 40% carbs
      proteinCalories = dailyCalories * 0.25;
      fatCalories = dailyCalories * 0.35;
      carbCalories = dailyCalories * 0.40;
    } else {
      // Balanced: 25% protein, 25% fat, 50% carbs
      proteinCalories = dailyCalories * 0.25;
      fatCalories = dailyCalories * 0.25;
      carbCalories = dailyCalories * 0.50;
    }

    return {
      'maxCalories': dailyCalories,
      'minProtein': proteinCalories / 4, // 4 calories per gram of protein
      'maxCarbs': carbCalories / 4, // 4 calories per gram of carbs
      'maxFat': fatCalories / 9, // 9 calories per gram of fat
      'maxSugar': hasLowSugar
          ? 25.0
          : 50.0, // Lower sugar limit for low sugar goal
    };
  }

  // Get BMI (Body Mass Index)
  static double calculateBMI(HealthProfile profile) {
    // BMI = weight(kg) / (height(m))^2
    double heightInMeters = profile.height / 100;
    return profile.weight / (heightInMeters * heightInMeters);
  }

  // Get BMI category
  static String getBMICategory(double bmi) {
    if (bmi < 18.5) {
      return 'Underweight';
    } else if (bmi < 25) {
      return 'Normal weight';
    } else if (bmi < 30) {
      return 'Overweight';
    } else {
      return 'Obese';
    }
  }

  // Get healthy weight range for height
  static Map<String, double> getHealthyWeightRange(double heightInCm) {
    double heightInMeters = heightInCm / 100;
    double heightSquared = heightInMeters * heightInMeters;

    return {
      'min': 18.5 * heightSquared, // Lower bound of normal BMI
      'max': 24.9 * heightSquared, // Upper bound of normal BMI
    };
  }
}
