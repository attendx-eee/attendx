class QualityThresholds {
  static const double minBrightness = 80;
  static const double maxBrightness = 180;

  static const double minContrast = 35;

  static const double minSharpness = 500;

  static const double minFaceOccupancy = 0.20;
  static const double maxFaceOccupancy = 0.45;

  static const double maxYaw = 20;
  static const double maxPitch = 20;
  static const double maxRoll = 15;
}

class DeviceQualityThresholds {
  static Map<String, double> sharpnessThresholds = {
    "Google Pixel 7": 300.0,
    "Google Pixel 6": 280.0,
    "Samsung SM-G991B": 350.0, // Galaxy S21
    "Samsung SM-G996B": 360.0, // Galaxy S21+
    "Apple iPhone14,2": 450.0, // iPhone 13 Pro
    "Apple iPhone14,5": 420.0, // iPhone 13
    "Default": 250.0,
  };

  static double getSharpnessThreshold(String deviceModel) {
    return sharpnessThresholds[deviceModel] ?? sharpnessThresholds["Default"]!;
  }

  
}


  
