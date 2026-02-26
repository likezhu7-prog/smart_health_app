# smart_health_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

# Smart Health App

The Smart Health App is a Flutter-based mobile application that integrates Fitbit and Apple HealthKit to collect patient vitals and sync them with the eHospital backend. Patients can log in, connect wearable devices, and view daily health metrics such as heart rate, steps, calories, and sleep.

# Features

Email-based login validated with the eHospital backend

Stores patient_id securely using SharedPreferences

Fitbit OAuth integration

Heart rate

Steps

Calories

Sleep

Apple HealthKit integration (iOS)

Heart rate

Steps

Sleep

Active energy

Automatic sync of vitals with the backend

Dashboard to choose Fitbit or Apple Health

Clean vitals display with timestamps and summaries

# Tech Stack

Flutter (Dart)

Fitbit Web API

Apple HealthKit

REST API (eHospital backend)

SharedPreferences

Material Design 3

# Project Structure
lib/
  Screens/
    login_screen.dart
    dashboard_screen.dart
    vitals_screen.dart
    vitals_history_screen.dart

  Services/
    fitbit_service.dart
    apple_health_service.dart
    e_hospital_auth_service.dart
    e_hospital_service.dart

  ui/
    app_theme.dart

# pubspec.yaml

# Running the App
Install dependencies
flutter pub get

iOS Setup and Xcode Commands
Install CocoaPods
sudo gem install cocoapods

Install iOS pods
cd ios
pod install
cd ..

Open Xcode workspace
open ios/Runner.xcworkspace


In Xcode:

Select your Team

Ensure the Bundle Identifier is valid

Enable HealthKit capability

Ensure Deployment Target matches Flutter

Run the app
flutter run

# Backend Requirements
POST /login

Returns:

patient_id

POST /vitals_history

Fields:

avg heart rate

latest heart rate

steps

calories

sleep

timestamp

source (fitbit or apple)

# Known Issues and Fixes
iOS build errors

Fixed by deleting:

ios/Pods/
ios/Podfile.lock
ios/build/


Then reinstalling pods.

Fitbit token expiry

Handled using reconnection flow and validation.

Apple Health permissions

Handled with permission checks and fallback.

Backend formatting issues

Timestamp and calorie formats standardized.

# Future Improvements

Vitals history charts

Notifications for abnormal vitals

Dark mode

Multi-user support