# Office Pal

Office Pal is a comprehensive, all-in-one college management system designed to streamline administrative tasks and enhance communication between students, faculty, and administrators. Built with Flutter and powered by Supabase, this application provides a centralized platform for managing student information, courses, exams, and faculty-related activities.

The primary goal of Office Pal is to modernize and simplify college administration by replacing manual, paper-based processes with an efficient, automated, and user-friendly digital solution. From student registration to exam seating arrangements, Office Pal offers a suite of powerful tools to improve productivity and reduce administrative overhead.

## Key Features

Office Pal offers a wide range of features tailored to the specific needs of different user roles within a college ecosystem.

### For Students

- **Simplified Login:** Easy access to the system using their unique registration number.
- **Course Management:** View and manage course registrations and academic progress.
- **Exam Information:** Access exam schedules, seating arrangements, and other relevant details.

### For Faculty

- **Dedicated Dashboard:** A centralized hub for managing courses, schedules, and student interactions.
- **Leave Management:** A streamlined system for requesting and tracking leave.
- **Course and Student Information:** Easy access to course materials and student details.

### For Superintendents

- **Comprehensive Dashboard:** An at-a-glance overview of all key metrics, including student enrollment, course distribution, and faculty availability.
- **Student and Faculty Management:** Tools for adding, editing, and managing student and faculty information.
- **Data Import/Export:** Seamlessly import data from CSV files and export reports when needed.
- **Notification System:** Real-time alerts for important events, such as leave requests and system updates.

### For Controllers

- **Exam Management:** A complete suite of tools for creating, scheduling, and managing exams.
- **Seating Arrangement Automation:** An intelligent algorithm that automatically generates optimized seating arrangements to prevent cheating and maximize space.
- **PDF Generation:** Instantly generate professional, print-ready seating charts and other exam-related documents.

## Architecture

Office Pal is built on a modern, scalable, and maintainable architecture that leverages the power of Flutter for the frontend and Supabase for the backend.

- **Frontend:** The user interface is developed using **Flutter**, a high-performance, cross-platform framework that allows for a native-like experience on both mobile and web.
- **Backend:** **Supabase**, an open-source Firebase alternative, provides a complete backend solution, including a PostgreSQL database, authentication, and real-time data synchronization.
- **State Management:** **Riverpod** is used for state management, ensuring a predictable and maintainable application state.
- **Routing:** **GoRouter** handles all navigation and routing within the application.

## Getting Started

Follow these steps to set up and run the project on your local machine.

### Prerequisites

- **Flutter SDK:** Version 3.6.0 or higher
- **Dart SDK:** Version 3.0.0 or higher
- **Supabase Account:** A free Supabase account is required for the backend.
- **IDE:** VS Code or Android Studio

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/MalluBeast69/office_pal.git
    ```

2.  **Navigate to the project directory:**
    ```bash
    cd office_pal
    ```

3.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

4.  **Create a `.env` file** in the root directory and add your Supabase credentials:
    ```
    SUPABASE_URL=your_supabase_url
    SUPABASE_ANON_KEY=your_supabase_anon_key
    ```

5.  **Run the application:**
    ```bash
    flutter run
    ```

## Project Structure

The project is organized into the following directories:

```
lib/
├── core/              # Core utilities, constants, and shared widgets
├── features/          # Feature-based modules (auth, student, faculty, etc.)
│   ├── auth/
│   ├── student/
│   ├── faculty/
│   ├── superintendent/
│   └── controller/
└── main.dart          # The main entry point of the application
```

- **`core/`**: This directory contains the fundamental building blocks of the application, such as constants, utility functions, and reusable widgets.
- **`features/`**: Each feature of the application is organized into its own module, following a clean architecture pattern. This includes pages, providers, repositories, and models specific to that feature.
- **`main.dart`**: The main entry point of the application, where the app is initialized and configured.

## Configuration

The application requires the following environment variables to be set in the `.env` file:

- **`SUPABASE_URL`**: The URL of your Supabase project.
- **`SUPABASE_ANON_KEY`**: The anonymous key for your Supabase project.

These variables are used to connect the Flutter application to the Supabase backend.

## Core Functionalities

Office Pal includes several advanced functionalities that are critical to its operation.

### Seating Arrangement Algorithm

The seating arrangement system is designed to automatically assign seats to students during exams, ensuring that no two students taking the same exam are seated next to each other. This is achieved through a sophisticated algorithm that:

1.  **Analyzes Hall and Student Data:** Gathers information about available halls, the number of students, and the exams they are taking.
2.  **Implements a Safety Check:** Ensures that students taking the same exam are not placed in adjacent seats (horizontally, vertically, or diagonally).
3.  **Optimizes Space:** Efficiently utilizes all available seats in the exam halls.

### PDF Generation System

The PDF generation system allows for the creation of professional and printable seating charts. The system:

1.  **Gathers Seating Information:** Collects all relevant data, including hall details, student names, and assigned seats.
2.  **Creates a Professional Layout:** Organizes the information in a clean, easy-to-read format, with clear headings, statistics, and color-coding.
3.  **Generates a Print-Ready PDF:** Produces a high-quality PDF document that can be easily shared and printed.

## License

This project is licensed under the **Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License**.

- ✅ You may view the code and share the link to this repository with credit.
- ❌ You may NOT modify, rebrand, use for commercial purposes, or redistribute altered versions of the software.

🔒 Unauthorized use may result in DMCA action.
