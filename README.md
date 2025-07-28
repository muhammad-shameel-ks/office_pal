# Office Pal

A comprehensive college management system built with Flutter and Supabase.

## Features

- **Multi-User Authentication**
  - Student login with registration number
  - Faculty login with faculty ID
  - Superintendent login with email/password

- **Student Management**
  - Add/Edit/Delete students
  - Import students via CSV
  - View student details and course registrations
  - Filter and search functionality

- **Course Management**
  - Add/Edit/Delete courses
  - Manage course registrations
  - Department-wise course organization

- **Faculty Features**
  - Leave request system
  - Course assignment
  - Availability status

- **Superintendent Dashboard**
  - Overview of students, courses, and departments
  - Notification system for leave requests
  - Data import/export capabilities

## Getting Started

### Prerequisites

- Flutter SDK (3.6.0 or higher)
- Dart SDK (3.0.0 or higher)
- Supabase account
- VS Code or Android Studio

### Installation

1. Clone the repository
   ```bash
   git clone https://github.com/MalluBeast69/office_pal.git
   ```

2. Navigate to project directory
   ```bash
   cd office_pal
   ```

3. Install dependencies
   ```bash
   flutter pub get
   ```

4. Create a `.env` file in the root directory and add your Supabase credentials
   ```
   SUPABASE_URL=your_supabase_url
   SUPABASE_ANON_KEY=your_supabase_anon_key
   ```

5. Run the app
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── core/
│   ├── constants.dart
│   └── ...
├── features/
│   ├── auth/
│   ├── student/
│   ├── faculty/
│   └── superintendent/
└── main.dart
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the **Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License**.

You may:
- ✅ View the code
- ✅ Share the link to this repository **with credit**

You may **NOT**:
- ❌ Modify or rebrand the software
- ❌ Use it commercially
- ❌ Redistribute altered versions

🔒 Unauthorized use may result in DMCA action.
