import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'student_exam_registration_page.dart';

class StudentManagementPage extends ConsumerStatefulWidget {
  final String? initialDepartment;

  const StudentManagementPage({
    super.key,
    this.initialDepartment,
  });

  @override
  ConsumerState<StudentManagementPage> createState() =>
      _StudentManagementPageState();
}

class _StudentManagementPageState extends ConsumerState<StudentManagementPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> filteredStudents = [];
  bool isLoading = true;
  bool isInitializing = true;
  String searchQuery = '';

  // Change from single selection to multiple selections
  Set<String> selectedDepartments = {};
  Set<int> selectedSemesters = {};
  Set<String> selectedRegStatuses = {};

  // Student selection for deletion
  Set<String> selectedStudentIds = {};
  bool selectAllChecked = false;

  List<String> departments = [];
  List<int> semesters = [];
  Map<String, List<Map<String, dynamic>>> studentCourses = {};
  Map<String, int> _departmentCounts = {};
  Map<int, int> _semesterCounts = {};
  Map<String, int> _regStatusCounts = {};

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Current section for sidebar
  String _currentSection = 'all';
  Timer? _debounce;

  // Add clear filters method early in the class
  void _clearFilters() {
    setState(() {
      selectedDepartments.clear();
      selectedSemesters.clear();
      selectedRegStatuses.clear();
      searchQuery = '';
      _currentSection = 'all';
      filterStudents();
    });
  }

  @override
  void initState() {
    super.initState();
    // Only add initialDepartment if it's not null and not empty
    if (widget.initialDepartment != null &&
        widget.initialDepartment!.isNotEmpty) {
      selectedDepartments.add(widget.initialDepartment!);
    }

    // Initialize with shorter animations for better performance
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // Reduced from 800ms
    );

    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeIn,
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // Reduced from 600ms
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05), // Reduce slide distance for performance
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start animations
    _fadeInController.forward();
    _slideController.forward();

    // Load data after animations are initialized
    loadStudents();
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    _slideController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> loadStudents() async {
    setState(() {
      isLoading = true;
      isInitializing = true;
      students = [];
      studentCourses = {};
    });

    try {
      developer.log('Loading students and courses...');

      // Load all students with optimized query
      final studentsResponse = await Supabase.instance.client
          .from('student')
          .select('student_reg_no, student_name, dept_id, semester')
          .order('student_reg_no');

      // Efficiently convert to list to avoid multiple conversions
      final allStudents = List<Map<String, dynamic>>.from(studentsResponse);

      developer.log('Loaded ${allStudents.length} students');

      // Load all registered courses with course details
      final coursesResponse =
          await Supabase.instance.client.from('registered_students').select('''
            student_reg_no,
            course_code,
            is_reguler,
            course:course_code (
              course_name,
              dept_id,
              credit
            )
          ''');

      developer.log('Loaded ${coursesResponse.length} course registrations');

      // Group courses by student more efficiently
      final Map<String, List<Map<String, dynamic>>> coursesByStudent = {};
      for (final course in List<Map<String, dynamic>>.from(coursesResponse)) {
        final studentId = course['student_reg_no'] as String;
        (coursesByStudent[studentId] ??= []).add(course);
      }

      developer.log(
          'Grouped courses by student: ${coursesByStudent.keys.length} students have courses');

      if (mounted) {
        setState(() {
          students = allStudents;
          studentCourses = coursesByStudent;

          // Extract unique departments and semesters from all loaded students
          // Use more efficient Set operations
          final deptSet = <String>{};
          final semSet = <int>{};

          for (final student in students) {
            deptSet.add(student['dept_id'].toString());
            semSet.add(student['semester'] as int);
          }

          departments = deptSet.toList()..sort();
          semesters = semSet.toList()..sort();

          // If initialDepartment is set but not in departments list, add it
          if (selectedDepartments.isEmpty &&
              widget.initialDepartment != null &&
              widget.initialDepartment!.isNotEmpty) {
            selectedDepartments.add(widget.initialDepartment!);
            if (!departments.contains(widget.initialDepartment)) {
              departments.add(widget.initialDepartment!);
              departments.sort();
            }
          }

          // Update loading state
          isLoading = false;
          isInitializing = false;

          // Filter the students
          filterStudents();
          _calculateFilterCounts();
        });
      }
    } catch (error) {
      developer.log('Error loading data: $error', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        isLoading = false;
        isInitializing = false;
      });
    }
  }

  void filterStudents() {
    developer.log('Filtering students...');
    developer.log(
        'Current filters - Departments: $selectedDepartments, Semesters: $selectedSemesters, RegStatuses: $selectedRegStatuses');

    // Use memoization to improve performance with large datasets
    // Only refilter if we have active filters or search
    final hasActiveFilters = selectedDepartments.isNotEmpty ||
        selectedSemesters.isNotEmpty ||
        selectedRegStatuses.isNotEmpty ||
        searchQuery.isNotEmpty;

    // If no filters are active, just use the full list
    if (!hasActiveFilters) {
      setState(() {
        filteredStudents = students;
      });
      return;
    }

    // Pre-process search query for better performance
    final lowercaseQuery = searchQuery.toLowerCase();

    // Create filtered list more efficiently
    final filtered = students.where((student) {
      final studentId = student['student_reg_no'] as String;

      // Check department first (most likely to filter out quickly)
      if (selectedDepartments.isNotEmpty &&
          !selectedDepartments.contains(student['dept_id'])) {
        return false;
      }

      // Check semester
      if (selectedSemesters.isNotEmpty &&
          !selectedSemesters.contains(student['semester'])) {
        return false;
      }

      // Search query check (can be expensive, so do it after other filters)
      if (lowercaseQuery.isNotEmpty) {
        final nameMatches = student['student_name']
            .toString()
            .toLowerCase()
            .contains(lowercaseQuery);
        final idMatches = studentId.toLowerCase().contains(lowercaseQuery);

        if (!nameMatches && !idMatches) {
          return false;
        }
      }

      // Registration status check (most complex check, do last)
      if (selectedRegStatuses.isNotEmpty) {
        final courses = studentCourses[studentId] ?? [];

        if (courses.isEmpty) {
          // Match 'Not Registered' status only
          return selectedRegStatuses.contains('Not Registered');
        } else if (selectedRegStatuses.contains('Regular') &&
            selectedRegStatuses.contains('Backlog')) {
          // Match all students with courses
          return true;
        } else if (selectedRegStatuses.contains('Regular')) {
          // All courses must be regular
          return courses.every((course) => course['is_reguler'] == true);
        } else if (selectedRegStatuses.contains('Backlog')) {
          // At least one backlog course
          return courses.any((course) => course['is_reguler'] == false);
        } else if (selectedRegStatuses.contains('Not Registered')) {
          // No courses
          return courses.isEmpty;
        }

        return false;
      }

      // If we got here, all checks passed
      return true;
    }).toList();

    setState(() {
      filteredStudents = filtered;
      developer.log('Filtered to ${filteredStudents.length} students');
    });
  }

  void _showImportOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Import Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Import Students'),
              subtitle: const Text('Add new students to the system'),
              onTap: () {
                Navigator.pop(context);
                _showFileTypeDialog('students');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.assignment),
              title: const Text('Import Course Registrations'),
              subtitle: const Text('Register students for courses'),
              onTap: () {
                Navigator.pop(context);
                _showFileTypeDialog('registrations');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFileTypeDialog(String importType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose File Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('CSV File'),
              onTap: () {
                Navigator.pop(context);
                if (importType == 'students') {
                  _importStudents(fileType: 'csv');
                } else {
                  _importRegistrations(fileType: 'csv');
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel File'),
              onTap: () {
                Navigator.pop(context);
                if (importType == 'students') {
                  _importStudents(fileType: 'excel');
                } else {
                  _importRegistrations(fileType: 'excel');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importStudents({required String fileType}) async {
    try {
      setState(() => isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: fileType == 'csv' ? ['csv'] : ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      developer.log('Selected file: ${file.name}');

      if (file.bytes == null) throw Exception('No file content');

      List<Map<String, dynamic>> students = [];

      if (fileType == 'csv') {
        final csvString = String.fromCharCodes(file.bytes!);
        final rows = csvString.split('\n');
        if (rows.isEmpty) throw Exception('Empty file');

        developer.log('CSV first row: "${rows.first}"');

        // Parse header and remove BOM if present
        final header = rows.first
            .trim()
            .replaceAll('\uFEFF', '') // Remove Unicode BOM
            .replaceAll('ï»¿', '') // Remove BOM character
            .split(',')
            .map((h) => h.trim().replaceAll('"', ''))
            .toList();
        developer.log('Split headers: $header');

        if (!_validateStudentHeaders(header)) {
          throw Exception(
              'Invalid CSV format. Expected headers: student_reg_no,student_name,dept_id,semester');
        }

        // Parse data rows
        for (final row in rows.skip(1).where((row) => row.trim().isNotEmpty)) {
          // Split by comma but preserve commas within quotes
          final columns = _splitCsvRow(row);
          developer.log('Parsed row: $columns');

          if (columns.length >= 4) {
            final semester = columns[3].trim().replaceAll('"', '');
            developer.log('Parsing semester value: "$semester"');

            students.add({
              'student_reg_no': columns[0].trim().replaceAll('"', ''),
              'student_name': columns[1].trim().replaceAll('"', ''),
              'dept_id': columns[2].trim().replaceAll('"', ''),
              'semester': int.parse(semester),
            });
          }
        }
      } else {
        // Parse Excel file
        final excelFile = excel.Excel.decodeBytes(file.bytes!);
        final sheet = excelFile.tables[excelFile.getDefaultSheet()!]!;

        // Validate header
        final headerRow = sheet.rows.first;
        if (!_validateStudentHeaders(
            headerRow.map((cell) => cell?.value.toString() ?? '').toList())) {
          throw Exception(
              'Invalid Excel format. Expected headers: student_reg_no,student_name,dept_id,semester');
        }

        // Parse data rows
        for (var row in sheet.rows.skip(1)) {
          if (row.any((cell) => cell?.value != null)) {
            students.add({
              'student_reg_no': row[0]?.value.toString().trim() ?? '',
              'student_name': row[1]?.value.toString().trim() ?? '',
              'dept_id': row[2]?.value.toString().trim() ?? '',
              'semester': int.parse(row[3]?.value.toString().trim() ?? '0'),
            });
          }
        }
      }

      await _validateAndImportStudents(students);
    } catch (error) {
      developer.log('Error importing students: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import students: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _importRegistrations({required String fileType}) async {
    try {
      setState(() => isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: fileType == 'csv' ? ['csv'] : ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      developer.log('Selected file: ${file.name}');

      if (file.bytes == null) throw Exception('No file content');

      List<Map<String, dynamic>> registrations = [];

      if (fileType == 'csv') {
        final csvString = String.fromCharCodes(file.bytes!);
        final rows = csvString.split('\n');
        if (rows.isEmpty) throw Exception('Empty file');

        developer.log('CSV first row: "${rows.first}"');

        // Parse header and remove BOM if present
        final header = rows.first
            .trim()
            .replaceAll('\uFEFF', '') // Remove Unicode BOM
            .replaceAll('ï»¿', '') // Remove BOM character
            .split(',')
            .map((h) => h.trim().replaceAll('"', ''))
            .toList();
        developer.log('Split headers: $header');

        if (!_validateRegistrationHeaders(header)) {
          throw Exception(
              'Invalid CSV format. Expected headers: student_reg_no,course_code,is_regular');
        }

        // Parse data rows
        for (final row in rows.skip(1).where((row) => row.trim().isNotEmpty)) {
          final columns = _splitCsvRow(row);
          developer.log('Parsed row: $columns');

          if (columns.length >= 5) {  // We need at least 5 columns, not 3
            // Get raw original value from column 4 (index is 0-based, so use 4)
            final rawValue = columns[4].trim();
            
            // Ensure properly handled as boolean
            bool isRegularValue;
            
            // Log raw data for debugging
            developer.log('Raw is_regular value from column 4: "$rawValue"');
            
            // Very explicit check for string values
            if (rawValue.toLowerCase() == 'true') {
              isRegularValue = true;
              developer.log('Found TRUE string - setting to true');
            } else if (rawValue.toUpperCase() == 'TRUE') {
              isRegularValue = true;
              developer.log('Found TRUE string (uppercase) - setting to true');
            } else if (rawValue == "true") {
              isRegularValue = true;
              developer.log('Found exact match "true" - setting to true');
            } else {
              isRegularValue = false;
              developer.log('No match for true value - setting to false');
            }
            
            registrations.add({
              'student_reg_no': columns[0].trim(),
              'course_code': columns[1].trim(),
              'is_reguler': isRegularValue,
            });
            
            developer.log('Added registration with is_reguler=$isRegularValue (${isRegularValue.runtimeType})');
          } else {
            developer.log('Row has insufficient columns: ${columns.length}. Expected at least 5 columns.');
          }
        }
      } else {
        // Parse Excel file
        final excelFile = excel.Excel.decodeBytes(file.bytes!);
        final sheet = excelFile.tables[excelFile.getDefaultSheet()!]!;

        // Validate header
        final headerRow = sheet.rows.first;
        if (!_validateRegistrationHeaders(
            headerRow.map((cell) => cell?.value.toString() ?? '').toList())) {
          throw Exception(
              'Invalid Excel format. Expected headers: student_reg_no,course_code,is_regular');
        }

        // Parse data rows
        for (var row in sheet.rows.skip(1)) {
          if (row.any((cell) => cell?.value != null) && row.length >= 5) {
            // Get raw original value from column 4 (index is 0-based, so use 4)
            final rawValue = row[4]?.value.toString().trim() ?? '';
            
            // Ensure properly handled as boolean
            bool isRegularValue;
            
            // Log raw data for debugging
            developer.log('Raw Excel is_regular value from column 4: "$rawValue"');
            
            // Very explicit check for string values
            if (rawValue.toLowerCase() == 'true') {
              isRegularValue = true;
              developer.log('Found TRUE string - setting to true');
            } else if (rawValue.toUpperCase() == 'TRUE') {
              isRegularValue = true;
              developer.log('Found TRUE string (uppercase) - setting to true');
            } else if (rawValue == "true") {
              isRegularValue = true;
              developer.log('Found exact match "true" - setting to true');
            } else {
              isRegularValue = false;
              developer.log('No match for true value - setting to false');
            }
            
            registrations.add({
              'student_reg_no': row[0]?.value.toString().trim() ?? '',
              'course_code': row[1]?.value.toString().trim() ?? '',
              'is_reguler': isRegularValue,
            });
            
            developer.log('Added Excel registration with is_reguler=$isRegularValue (${isRegularValue.runtimeType})');
          } else if (row.length < 5) {
            developer.log('Excel row has insufficient columns: ${row.length}. Expected at least 5 columns.');
          }
        }
      }

      await _validateAndImportRegistrations(registrations);
    } catch (error) {
      developer.log('Error importing registrations: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to import registrations: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  bool _validateStudentHeaders(List<String> headers) {
    final requiredHeaders = [
      'student_reg_no',
      'student_name',
      'dept_id',
      'semester'
    ];

    // Clean headers by removing quotes, whitespace, and BOM character
    final cleanedHeaders = headers.map((h) {
      final cleaned = h
          .trim()
          .toLowerCase()
          .replaceAll('"', '')
          .replaceAll("'", '')
          .replaceAll('ï»¿', '') // Remove BOM character
          .replaceAll('\uFEFF', ''); // Remove Unicode BOM
      developer.log('Original header: "$h" -> Cleaned header: "$cleaned"');
      return cleaned;
    }).toList();

    developer.log('Required headers: $requiredHeaders');
    developer.log('Cleaned headers: $cleanedHeaders');

    // Check if we have enough headers
    if (cleanedHeaders.length < requiredHeaders.length) {
      developer.log(
          'Not enough headers: expected ${requiredHeaders.length}, got ${cleanedHeaders.length}');
      return false;
    }

    // Check each required header
    for (final required in requiredHeaders) {
      final found = cleanedHeaders.contains(required);
      developer
          .log('Checking for "$required": ${found ? "Found" : "Not found"}');
      if (!found) return false;
    }

    return true;
  }

  bool _validateRegistrationHeaders(List<String> headers) {
    // Now account for all 5 columns including timestamps
    final requiredHeaders = ['student_reg_no', 'course_code', 'created_at', 'updated_at', 'is_regular'];

    // Clean headers by removing quotes and whitespace
    final cleanedHeaders = headers.map((h) {
      final cleaned = h
          .trim()
          .toLowerCase()
          .replaceAll('"', '')
          .replaceAll("'", '')
          .replaceAll('is_reguler', 'is_regular') // Handle both spellings
          .replaceAll('\uFEFF', '')  // Remove Unicode BOM
          .replaceAll('ï»¿', '');    // Remove BOM character
      developer.log('Original header: "$h" -> Cleaned header: "$cleaned"');
      return cleaned;
    }).toList();

    developer.log('Required headers: $requiredHeaders');
    developer.log('Cleaned headers: $cleanedHeaders');

    // Check if we have enough headers
    if (cleanedHeaders.length < requiredHeaders.length) {
      developer.log(
          'Not enough headers: expected ${requiredHeaders.length}, got ${cleanedHeaders.length}');
      return false;
    }

    // Ensure the critical headers are present (student_reg_no, course_code, is_regular)
    final criticalHeaders = ['student_reg_no', 'course_code', 'is_regular'];
    for (final required in criticalHeaders) {
      final found = cleanedHeaders.contains(required);
      developer
          .log('Checking for critical header "$required": ${found ? "Found" : "Not found"}');
      if (!found) return false;
    }

    return true;
  }

  Future<void> _validateAndImportStudents(
      List<Map<String, dynamic>> students) async {
    if (students.isEmpty) {
      throw Exception('No valid student records found in the file');
    }

    // Get valid departments from database
    final departmentsResponse =
        await Supabase.instance.client.from('departments').select('dept_id');
    final validDepartments = List<String>.from(
        departmentsResponse.map((dept) => dept['dept_id'].toString()));

    // Get existing student IDs to check for duplicates
    final existingStudentsResponse =
        await Supabase.instance.client.from('student').select('student_reg_no');
    final existingStudentIds = List<String>.from(
        existingStudentsResponse.map((s) => s['student_reg_no'].toString()));

    final errors = <String>[];
    final validStudents = <Map<String, dynamic>>[];
    int rowNumber = 1;

    for (final student in students) {
      rowNumber++;
      try {
        final studentId = student['student_reg_no'].toString().toUpperCase();
        final deptId = student['dept_id'].toString().toUpperCase();
        final semester = student['semester'];

        // Check for duplicate in existing students
        if (existingStudentIds.contains(studentId)) {
          errors.add('Row $rowNumber: Student ID $studentId already exists');
          validStudents.add({...student, 'has_error': true});
          continue;
        }

        // Check for duplicate in current import
        if (validStudents.any((s) => s['student_reg_no'] == studentId)) {
          errors.add(
              'Row $rowNumber: Duplicate student ID $studentId in import file');
          validStudents.add({...student, 'has_error': true});
          continue;
        }

        // Validate department
        if (!validDepartments.contains(deptId)) {
          errors.add('Row $rowNumber: Invalid department ID: $deptId');
          validStudents.add({...student, 'has_error': true});
          continue;
        }

        // Validate semester
        if (semester < 1 || semester > 8) {
          errors.add(
              'Row $rowNumber: Invalid semester (should be a number between 1 and 8)');
          validStudents.add({...student, 'has_error': true});
          continue;
        }

        validStudents.add({...student, 'has_error': false});
      } catch (e) {
        errors.add('Row $rowNumber: ${e.toString()}');
        validStudents.add({...student, 'has_error': true});
      }
    }

    // Show preview dialog
    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) => PreviewDialog(
        students: validStudents,
        errors: errors,
      ),
    );

    if (shouldImport == true) {
      // Filter out students with errors before importing
      final studentsToImport =
          validStudents.where((s) => !s['has_error']).map((s) {
        final student = Map<String, dynamic>.from(s);
        student.remove('has_error');
        return student;
      }).toList();

      await Supabase.instance.client.from('student').insert(studentsToImport);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully imported ${studentsToImport.length} students'),
            backgroundColor: Colors.green,
          ),
        );
        loadStudents();
      }
    }
  }

  Future<void> _validateAndImportRegistrations(
      List<Map<String, dynamic>> registrations) async {
    if (registrations.isEmpty) {
      throw Exception('No valid registration records found in the file');
    }
    
    // Debug log all registrations as they come in
    developer.log('Raw registrations to import:');
    for (var reg in registrations) {
      developer.log('  ${reg['student_reg_no']}, ${reg['course_code']}, isRegular=${reg['is_reguler']} (${reg['is_reguler'].runtimeType})');
    }

    // Get valid student IDs
    final studentsResponse =
        await Supabase.instance.client.from('student').select('student_reg_no');
    final validStudentIds = List<String>.from(studentsResponse
        .map((s) => s['student_reg_no'].toString().toUpperCase()));

    // Get valid course codes with case preserved
    final coursesResponse =
        await Supabase.instance.client.from('course').select('course_code');
    final validCourseCodes = List<String>.from(
        coursesResponse.map((c) => c['course_code'].toString().trim()));

    developer.log('Available courses in DB: $validCourseCodes');

    // Create case-sensitive lookup map with trimmed codes
    final courseCodeMap = {
      for (var code in validCourseCodes) code.trim(): code.trim()
    };

    // Get existing registrations to check for duplicates
    final existingRegistrationsResponse = await Supabase.instance.client
        .from('registered_students')
        .select('student_reg_no, course_code');
    final existingRegistrations =
        List<Map<String, dynamic>>.from(existingRegistrationsResponse);

    final errors = <String>[];
    final validRegistrations = <Map<String, dynamic>>[];
    int rowNumber = 1;

    for (final registration in registrations) {
      rowNumber++;
      try {
        final studentId =
            registration['student_reg_no'].toString().toUpperCase();
        final courseCode = registration['course_code'].toString().trim();
        final isRegular = registration['is_reguler']; // Keep as is, already correctly parsed

        developer.log('Validating row $rowNumber - Course: "$courseCode", Is Regular: $isRegular (${isRegular.runtimeType})');

        // Validate student ID
        if (!validStudentIds.contains(studentId)) {
          errors.add('Row $rowNumber: Student ID $studentId does not exist');
          validRegistrations.add({...registration, 'has_error': true});
          continue;
        }

        // Validate course code (exact match after trimming)
        if (!courseCodeMap.containsKey(courseCode)) {
          errors
              .add('Row $rowNumber: Course code "$courseCode" does not exist');
          developer.log(
              'Course "$courseCode" not found in valid courses: $validCourseCodes');
          validRegistrations.add({...registration, 'has_error': true});
          continue;
        }

        // Get the correct case for the course code
        final correctCaseCode = courseCodeMap[courseCode]!;

        // Check for existing registration (case-sensitive comparison after trimming)
        if (existingRegistrations.any((r) =>
            r['student_reg_no'].toString().toUpperCase() == studentId &&
            r['course_code'].toString().trim() == correctCaseCode)) {
          errors.add(
              'Row $rowNumber: Student $studentId is already registered for course $correctCaseCode');
          validRegistrations.add({...registration, 'has_error': true});
          continue;
        }

        // Check for duplicate in current import
        if (validRegistrations.any((r) =>
            r['student_reg_no'].toString().toUpperCase() == studentId &&
            r['course_code'].toString().trim() == correctCaseCode)) {
          errors.add(
              'Row $rowNumber: Duplicate registration for student $studentId and course $correctCaseCode in import file');
          validRegistrations.add({...registration, 'has_error': true});
          continue;
        }

        // Add registration with correct case for course code
        validRegistrations.add({
          'student_reg_no': studentId,
          'course_code': correctCaseCode,
          'is_reguler': isRegular,
          'has_error': false
        });
      } catch (e) {
        errors.add('Row $rowNumber: ${e.toString()}');
        validRegistrations.add({...registration, 'has_error': true});
      }
    }

    // Show preview dialog with debugging information
    developer.log('Preview registrations:');
    for (var reg in validRegistrations) {
      if (!reg['has_error']) {
        developer.log('  ${reg['student_reg_no']}, ${reg['course_code']}, isRegular=${reg['is_reguler']} (${reg['is_reguler'].runtimeType})');
      }
    }
    
    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) => PreviewDialog(
        students: validRegistrations,
        errors: errors,
      ),
    );

    if (shouldImport == true) {
      // Filter out registrations with errors before importing
      final registrationsToImport =
          validRegistrations.where((r) => !r['has_error']).map((r) {
        final registration = Map<String, dynamic>.from(r);
        registration.remove('has_error');
        
        // Ensure is_reguler is boolean
        final isRegular = registration['is_reguler'];
        if (isRegular is! bool) {
          developer.log('WARNING: is_reguler is not boolean at insertion: $isRegular (${isRegular.runtimeType})');
          if (isRegular.toString().toLowerCase() == 'true') {
            registration['is_reguler'] = true;
          } else {
            registration['is_reguler'] = false;
          }
        }
        
        return registration;
      }).toList();

      // Log what we're actually inserting to the database
      developer.log('Inserting registrations:');
      for (var reg in registrationsToImport) {
        developer.log('FINAL INSERT: ${reg['student_reg_no']}, ${reg['course_code']}, isRegular=${reg['is_reguler']} (${reg['is_reguler'].runtimeType})');
      }

      await Supabase.instance.client
          .from('registered_students')
          .insert(registrationsToImport);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully imported ${registrationsToImport.length} registrations'),
            backgroundColor: Colors.green,
          ),
        );
        loadStudents();
      }
    }
  }

  // CSV Parser that preserves commas within quotes
  List<String> _splitCsvRow(String row) {
    List<String> columns = [];
    bool inQuotes = false;
    StringBuffer currentValue = StringBuffer();

    for (int i = 0; i < row.length; i++) {
      String char = row[i];

      if (char == '"') {
        // Toggle quote state
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        // End of column outside quotes
        columns.add(currentValue.toString());
        currentValue.clear();
      } else {
        // Add to current value
        currentValue.write(char);
      }
    }

    // Add the last column
    columns.add(currentValue.toString());

    return columns;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final theme = Theme.of(context);
    const isWeb = kIsWeb;

    return Scaffold(
      appBar: isSmallScreen
          ? AppBar(
              title: Text(
                'Student Management',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
              actions: [
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primaryColor,
                        ),
                      ),
                    ),
                  )
              ],
            )
          : null,
      body: isInitializing
          ? _buildLoadingScreen()
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade50,
                    Colors.white,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSmallScreen) _buildSidebar(),
                    Expanded(
                      child: Column(
                        children: [
                          if (!isSmallScreen) _buildAppBar(theme, isWeb),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: loadStudents,
                              child: CustomScrollView(
                                slivers: [
                                  // Only apply animations on first render, not on refreshes
                                  if (isInitializing)
                                    SliverFadeTransition(
                                      opacity: _fadeInAnimation,
                                      sliver: SliverToBoxAdapter(
                                        child: SlideTransition(
                                          position: _slideAnimation,
                                          child: _buildContent(isSmallScreen),
                                        ),
                                      ),
                                    )
                                  else
                                    SliverToBoxAdapter(
                                      child: _buildContent(isSmallScreen),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      drawer: isSmallScreen
          ? Drawer(
              child: _buildSidebar(),
            )
          : null,
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade100,
            Colors.blue.shade50,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LoadingAnimationWidget.staggeredDotsWave(
              color: Colors.blue,
              size: 50,
            ),
            const SizedBox(height: 24),
            Text(
              'Student Management',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading students...',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 3,
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 280,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.school,
                      size: 32,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Students',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Add Clear Filters button
            if (selectedDepartments.isNotEmpty ||
                selectedSemesters.isNotEmpty ||
                selectedRegStatuses.isNotEmpty ||
                searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear All Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    minimumSize: const Size(double.infinity, 40),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSidebarItem(
                      'all',
                      'All Students',
                      Icons.people,
                      onTap: () {
                        setState(() {
                          _currentSection = 'all';
                          _clearFilters();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'DEPARTMENTS',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...departments.map((dept) => _buildSidebarItem(
                          'dept_$dept',
                          dept,
                          Icons.business,
                          isMultiSelect: true,
                          isSelected: selectedDepartments.contains(dept),
                          onTap: () {
                            setState(() {
                              _currentSection = 'departments';
                              // Toggle this department in the selection
                              if (selectedDepartments.contains(dept)) {
                                selectedDepartments.remove(dept);
                              } else {
                                selectedDepartments.add(dept);
                              }
                              filterStudents();
                            });
                          },
                        )),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'SEMESTERS',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...semesters.map((sem) => _buildSidebarItem(
                          'sem_$sem',
                          'Semester $sem',
                          Icons.calendar_today,
                          isMultiSelect: true,
                          isSelected: selectedSemesters.contains(sem),
                          onTap: () {
                            setState(() {
                              _currentSection = 'semesters';
                              // Toggle this semester in the selection
                              if (selectedSemesters.contains(sem)) {
                                selectedSemesters.remove(sem);
                              } else {
                                selectedSemesters.add(sem);
                              }
                              filterStudents();
                            });
                          },
                        )),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'REGISTRATION STATUS',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSidebarItem(
                      'reg_regular',
                      'Regular',
                      Icons.check_circle_outline,
                      isMultiSelect: true,
                      isSelected: selectedRegStatuses.contains('Regular'),
                      onTap: () {
                        setState(() {
                          _currentSection = 'registration';
                          // Toggle Regular status
                          if (selectedRegStatuses.contains('Regular')) {
                            selectedRegStatuses.remove('Regular');
                          } else {
                            selectedRegStatuses.add('Regular');
                          }
                          filterStudents();
                        });
                      },
                    ),
                    _buildSidebarItem(
                      'reg_backlog',
                      'Backlog',
                      Icons.warning_amber_outlined,
                      isMultiSelect: true,
                      isSelected: selectedRegStatuses.contains('Backlog'),
                      onTap: () {
                        setState(() {
                          _currentSection = 'registration';
                          // Toggle Backlog status
                          if (selectedRegStatuses.contains('Backlog')) {
                            selectedRegStatuses.remove('Backlog');
                          } else {
                            selectedRegStatuses.add('Backlog');
                          }
                          filterStudents();
                        });
                      },
                    ),
                    _buildSidebarItem(
                      'reg_none',
                      'Not Registered',
                      Icons.cancel_outlined,
                      isMultiSelect: true,
                      isSelected:
                          selectedRegStatuses.contains('Not Registered'),
                      onTap: () {
                        setState(() {
                          _currentSection = 'registration';
                          // Toggle Not Registered status
                          if (selectedRegStatuses.contains('Not Registered')) {
                            selectedRegStatuses.remove('Not Registered');
                          } else {
                            selectedRegStatuses.add('Not Registered');
                          }
                          filterStudents();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.grey.shade200),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: Icon(
                  Icons.arrow_back,
                  color: Colors.grey.shade600,
                ),
                title: Text(
                  'Back to Dashboard',
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    String id,
    String title,
    IconData icon, {
    required VoidCallback onTap,
    bool isMultiSelect = false,
    bool isSelected = false,
  }) {
    // For All Students, use the old selection logic
    if (id == 'all') {
      isSelected = _currentSection == id;
    }
    // For multi-select items, isSelected is passed in from the parent

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.shade50 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                isMultiSelect && isSelected
                    ? Icon(
                        Icons.check_box,
                        size: 20,
                        color: Colors.blue.shade700,
                      )
                    : isMultiSelect
                        ? Icon(
                            Icons.check_box_outline_blank,
                            size: 20,
                            color: Colors.grey.shade600,
                          )
                        : Icon(
                            icon,
                            size: 20,
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
                          ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? Colors.blue.shade700
                          : Colors.grey.shade800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (id.startsWith('dept_') ||
                    id.startsWith('sem_') ||
                    id.startsWith('reg_'))
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue.shade100
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _getCountForFilter(id),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.blue.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _calculateFilterCounts() {
    _departmentCounts.clear();
    _semesterCounts.clear();
    _regStatusCounts.clear();

    _regStatusCounts['Regular'] = 0;
    _regStatusCounts['Backlog'] = 0;
    _regStatusCounts['Not Registered'] = 0;

    for (final student in students) {
      final deptId = student['dept_id'].toString();
      final semester = student['semester'] as int;
      final studentId = student['student_reg_no'] as String;
      final courses = studentCourses[studentId] ?? [];

      _departmentCounts[deptId] = (_departmentCounts[deptId] ?? 0) + 1;
      _semesterCounts[semester] = (_semesterCounts[semester] ?? 0) + 1;

      if (courses.isEmpty) {
        _regStatusCounts['Not Registered'] =
            (_regStatusCounts['Not Registered'] ?? 0) + 1;
      } else {
        final hasBacklog = courses.any((c) => c['is_reguler'] == false);
        if (hasBacklog) {
          _regStatusCounts['Backlog'] = (_regStatusCounts['Backlog'] ?? 0) + 1;
        } else {
          _regStatusCounts['Regular'] = (_regStatusCounts['Regular'] ?? 0) + 1;
        }
      }
    }
  }

  String _getCountForFilter(String id) {
    if (id == 'all') return students.length.toString();

    if (id.startsWith('dept_')) {
      final dept = id.substring(5);
      return (_departmentCounts[dept] ?? 0).toString();
    }

    if (id.startsWith('sem_')) {
      final sem = int.parse(id.substring(4));
      return (_semesterCounts[sem] ?? 0).toString();
    }

    if (id == 'reg_regular') {
      return (_regStatusCounts['Regular'] ?? 0).toString();
    }

    if (id == 'reg_backlog') {
      return (_regStatusCounts['Backlog'] ?? 0).toString();
    }
    
    if (id == 'reg_none') {
      return (_regStatusCounts['Not Registered'] ?? 0).toString();
    }

    return '0';
  }

  Widget _buildAppBar(ThemeData theme, bool isWeb) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isWeb
            ? Colors.white.withOpacity(0.8)
            : theme.scaffoldBackgroundColor,
        boxShadow: [
          if (!isLoading)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Student Management',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                ),
              ),
            ),
          Flexible(
            child: SizedBox(
              width: 240,
              height: 40,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search students...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    setState(() {
                      searchQuery = value;
                      filterStudents();
                    });
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSmallScreen) _buildSearchField(),
          if (!isSmallScreen) _buildHeaderSection(),
          const SizedBox(height: 16),
          _buildFilterChips(),
          const SizedBox(height: 16),
          _buildStudentList(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search students...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (value) {
          if (_debounce?.isActive ?? false) _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), () {
            setState(() {
              searchQuery = value;
              filterStudents();
            });
          });
        },
      ),
    );
  }

  Widget _buildHeaderSection() {
    // Build title based on active filters
    List<String> filterParts = [];

    if (selectedDepartments.isNotEmpty) {
      if (selectedDepartments.length == 1) {
        filterParts.add('Department: ${selectedDepartments.first}');
      } else {
        filterParts.add('${selectedDepartments.length} Departments');
      }
    }

    if (selectedSemesters.isNotEmpty) {
      if (selectedSemesters.length == 1) {
        filterParts.add('Semester ${selectedSemesters.first}');
      } else {
        filterParts.add('${selectedSemesters.length} Semesters');
      }
    }

    if (selectedRegStatuses.isNotEmpty) {
      filterParts.add('${selectedRegStatuses.join('/')} Students');
    }

    String title =
        filterParts.isNotEmpty ? filterParts.join(', ') : 'All Students';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ${filteredStudents.length} students',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import'),
                  onPressed: _showImportOptions,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Student'),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const AddStudentDialog(),
                  ).then((value) {
                    if (value == true) {
                      loadStudents();
                    }
                  }),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Department chips
        ...selectedDepartments.map(
          (dept) => FilterChip(
            label: Text('Dept: $dept'),
            onSelected: (_) {
              setState(() {
                selectedDepartments.remove(dept);
                filterStudents();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                selectedDepartments.remove(dept);
                filterStudents();
              });
            },
          ),
        ),

        // Semester chips
        ...selectedSemesters.map(
          (sem) => FilterChip(
            label: Text('Semester: $sem'),
            onSelected: (_) {
              setState(() {
                selectedSemesters.remove(sem);
                filterStudents();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                selectedSemesters.remove(sem);
                filterStudents();
              });
            },
          ),
        ),

        // Registration status chips
        ...selectedRegStatuses.map(
          (status) => FilterChip(
            label: Text('Status: $status'),
            onSelected: (_) {
              setState(() {
                selectedRegStatuses.remove(status);
                filterStudents();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                selectedRegStatuses.remove(status);
                filterStudents();
              });
            },
          ),
        ),

        // Search query chip
        if (searchQuery.isNotEmpty)
          FilterChip(
            label: Text('Search: $searchQuery'),
            onSelected: (_) {
              setState(() {
                searchQuery = '';
                filterStudents();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                searchQuery = '';
                filterStudents();
              });
            },
          ),

        // Clear all button
        if (selectedDepartments.isNotEmpty ||
            selectedSemesters.isNotEmpty ||
            selectedRegStatuses.isNotEmpty ||
            searchQuery.isNotEmpty)
          ActionChip(
            label: const Text('Clear All'),
            onPressed: _clearFilters,
            avatar: const Icon(Icons.clear_all, size: 18),
            backgroundColor: Colors.red.shade50,
            labelStyle: TextStyle(color: Colors.red.shade700),
          ),
      ],
    );
  }

  Widget _buildStudentList() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    if (filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No students found',
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            if (searchQuery.isNotEmpty ||
                selectedDepartments.isNotEmpty ||
                selectedSemesters.isNotEmpty ||
                selectedRegStatuses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Try adjusting your filters',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Show delete button if students are selected
    final hasSelectedStudents = selectedStudentIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selection management UI
        if (hasSelectedStudents)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column( // Use Column for better responsiveness on small screens
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '${selectedStudentIds.length} student${selectedStudentIds.length > 1 ? "s" : ""} selected',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 8), // Add some spacing
                    Wrap( // Use Wrap for buttons to allow them to flow
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.deselect),
                          label: const Text('Clear Selection'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                          onPressed: () {
                            setState(() {
                              selectedStudentIds.clear();
                              selectAllChecked = false;
                            });
                          },
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.delete),
                          label: const Text('Delete Selected'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                          ),
                          onPressed: _showDeleteConfirmation,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (isSmallScreen)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredStudents.length,
            itemBuilder: (context, index) {
              final student = filteredStudents[index];
              return _buildStudentCard(student);
            },
          )
        else
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Column(
                children: [
                  _buildStudentListHeader(),
                  SizedBox(
                    height: 400, // Fixed height for the list
                    child: ListView.builder(
                      itemCount: filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = filteredStudents[index];
                        return _buildStudentListRow(student);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFloatingActionButton() {
    return MediaQuery.of(context).size.width < 600
        ? FloatingActionButton(
            onPressed: () => showDialog(
              context: context,
              builder: (context) => const AddStudentDialog(),
            ).then((value) {
              if (value == true) {
                loadStudents();
              }
            }),
            child: const Icon(Icons.add),
          )
        : const SizedBox.shrink();
  }

  Widget _buildStudentListHeader() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selectAllChecked,
            onChanged: (value) {
              setState(() {
                selectAllChecked = value ?? false;
                if (selectAllChecked) {
                  selectedStudentIds = filteredStudents
                      .map((s) => s['student_reg_no'] as String)
                      .toSet();
                } else {
                  selectedStudentIds.clear();
                }
              });
            },
          ),
          const Expanded(child: Text('Reg No', style: TextStyle(fontWeight: FontWeight.bold))),
          const Expanded(flex: 2, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
          if (!isSmallScreen) ...[
            const Expanded(child: Text('Department', style: TextStyle(fontWeight: FontWeight.bold))),
            const Expanded(child: Text('Semester', style: TextStyle(fontWeight: FontWeight.bold))),
            const Expanded(child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          const SizedBox(width: 192, child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildStudentListRow(Map<String, dynamic> student) {
    final studentId = student['student_reg_no'] as String;
    final courses = studentCourses[studentId] ?? [];
    final isSelected = selectedStudentIds.contains(studentId);

    bool hasBacklog = false;
    String statusText = 'Not Registered';
    Color statusColor = Colors.grey;

    if (courses.isNotEmpty) {
      hasBacklog = courses.any((course) => course['is_reguler'] == false);
      if (hasBacklog) {
        statusText = 'Backlog';
        statusColor = Colors.orange;
      } else {
        statusText = 'Regular';
        statusColor = Colors.green;
      }
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            selectedStudentIds.remove(studentId);
          } else {
            selectedStudentIds.add(studentId);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: isSmallScreen
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value ?? false) {
                              selectedStudentIds.add(studentId);
                            } else {
                              selectedStudentIds.remove(studentId);
                            }
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          studentId,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          student['student_name'] as String,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 48.0, top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dept: ${student['dept_id'] as String}'),
                        Text('Sem: ${student['semester'].toString()}'),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility, size: 20),
                              tooltip: 'View Courses',
                              onPressed: () => _showCoursesDialog(student),
                              splashRadius: 24,
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              tooltip: 'Edit Student',
                              onPressed: () => _showEditDialog(student),
                              splashRadius: 24,
                            ),
                            IconButton(
                              icon: const Icon(Icons.assignment, size: 20),
                              tooltip: 'Exam Registration',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => StudentExamRegistrationPage(
                                      studentId: studentId,
                                    ),
                                  ),
                                );
                              },
                              splashRadius: 24,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                              tooltip: 'Delete Student',
                              onPressed: () {
                                setState(() {
                                  selectedStudentIds = {studentId};
                                });
                                _showDeleteConfirmation();
                              },
                              splashRadius: 24,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value ?? false) {
                          selectedStudentIds.add(studentId);
                        } else {
                          selectedStudentIds.remove(studentId);
                        }
                      });
                    },
                  ),
                  Expanded(child: Text(studentId)),
                  Expanded(flex: 2, child: Text(student['student_name'] as String)),
                  Expanded(child: Text(student['dept_id'] as String)),
                  Expanded(child: Text(student['semester'].toString())),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 192,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility, size: 20),
                          tooltip: 'View Courses',
                          onPressed: () => _showCoursesDialog(student),
                          splashRadius: 24,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Edit Student',
                          onPressed: () => _showEditDialog(student),
                          splashRadius: 24,
                        ),
                        IconButton(
                          icon: const Icon(Icons.assignment, size: 20),
                          tooltip: 'Exam Registration',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => StudentExamRegistrationPage(
                                  studentId: studentId,
                                ),
                              ),
                            );
                          },
                          splashRadius: 24,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                          tooltip: 'Delete Student',
                          onPressed: () {
                            setState(() {
                              selectedStudentIds = {studentId};
                            });
                            _showDeleteConfirmation();
                          },
                          splashRadius: 24,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    final studentId = student['student_reg_no'] as String;
    final courses = studentCourses[studentId] ?? [];
    final isSelected = selectedStudentIds.contains(studentId);

    bool hasBacklog = false;
    String statusText = 'Not Registered';
    Color statusColor = Colors.grey;

    if (courses.isNotEmpty) {
      hasBacklog = courses.any((course) => course['is_reguler'] == false);
      if (hasBacklog) {
        statusText = 'Backlog';
        statusColor = Colors.orange;
      } else {
        statusText = 'Regular';
        statusColor = Colors.green;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              selectedStudentIds.remove(studentId);
            } else {
              selectedStudentIds.add(studentId);
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value ?? false) {
                          selectedStudentIds.add(studentId);
                        } else {
                          selectedStudentIds.remove(studentId);
                        }
                      });
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['student_name'] as String,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          studentId,
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dept: ${student['dept_id'] as String}'),
                      Text('Sem: ${student['semester'].toString()}'),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility, size: 20),
                    tooltip: 'View Courses',
                    onPressed: () => _showCoursesDialog(student),
                    splashRadius: 24,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Edit Student',
                    onPressed: () => _showEditDialog(student),
                    splashRadius: 24,
                  ),
                  IconButton(
                    icon: const Icon(Icons.assignment, size: 20),
                    tooltip: 'Exam Registration',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => StudentExamRegistrationPage(
                            studentId: studentId,
                          ),
                        ),
                      );
                    },
                    splashRadius: 24,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                    tooltip: 'Delete Student',
                    onPressed: () {
                      setState(() {
                        selectedStudentIds = {studentId};
                      });
                      _showDeleteConfirmation();
                    },
                    splashRadius: 24,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCoursesDialog(Map<String, dynamic> student) {
    final studentId = student['student_reg_no'] as String;
    final courses = studentCourses[studentId] ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Courses for ${student['student_name']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: courses.isEmpty
              ? Center(
                  child: Text(
                    'No courses registered',
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade600,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: courses.length,
                  itemBuilder: (context, index) {
                    final course = courses[index];
                    final courseDetails =
                        course['course'] as Map<String, dynamic>;
                    final isRegular = course['is_reguler'] as bool;

                    return ListTile(
                      title: Text(
                        '${courseDetails['course_code']}: ${courseDetails['course_name']}',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Credit: ${courseDetails['credit']} | Department: ${courseDetails['dept_id']}',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isRegular
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isRegular ? Colors.green : Colors.orange,
                          ),
                        ),
                        child: Text(
                          isRegular ? 'Regular' : 'Backlog',
                          style: GoogleFonts.poppins(
                            color: isRegular ? Colors.green : Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> student) {
    final editFormKey = GlobalKey<FormState>();
    final regNoController =
        TextEditingController(text: student['student_reg_no'] as String);
    final nameController =
        TextEditingController(text: student['student_name'] as String);
    String selectedDepartment = student['dept_id'] as String;
    int selectedSemester = student['semester'] as int;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'Edit Student',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            content: SizedBox(
              width: 400,
              child: Form(
                key: editFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: regNoController,
                      decoration: const InputDecoration(
                        labelText: 'Registration Number',
                        hintText: 'e.g., CSE1801',
                      ),
                      readOnly:
                          true, // Registration number shouldn't be editable
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Student Name',
                        hintText: 'Full name',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter student name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<dynamic>(
                      future: Supabase.instance.client
                          .from('departments')
                          .select('dept_id, dept_name')
                          .order('dept_name'),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return Text(
                              'Error loading departments: ${snapshot.error}');
                        }

                        final departments =
                            (snapshot.data as List<dynamic>?) ?? [];

                        return DropdownButtonFormField<String>(
                          value: selectedDepartment,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                          ),
                          items: departments.map((dept) {
                            return DropdownMenuItem<String>(
                              value: dept['dept_id'] as String,
                              child: Expanded(
                                child: Text(
                                    '${dept['dept_id']} - ${dept['dept_name']}'),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => selectedDepartment = value!);
                          },
                          validator: (value) {
                            if (value == null) {
                              return 'Please select a department';
                            }
                            return null;
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: selectedSemester,
                      decoration: const InputDecoration(
                        labelText: 'Semester',
                      ),
                      items: [1, 2, 3, 4, 5, 6, 7, 8].map((semester) {
                        return DropdownMenuItem<int>(
                          value: semester,
                          child: Text('Semester $semester'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedSemester = value!);
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Please select a semester';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (editFormKey.currentState!.validate()) {
                          setState(() => isLoading = true);
                          try {
                            await Supabase.instance.client
                                .from('student')
                                .update({
                              'student_name': nameController.text.trim(),
                              'dept_id': selectedDepartment,
                              'semester': selectedSemester,
                            }).eq('student_reg_no', student['student_reg_no']);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Student updated successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              Navigator.pop(context, true);
                            }
                          } catch (error) {
                            setState(() => isLoading = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Failed to update student: ${error.toString()}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Save',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          );
        });
      },
    ).then((value) {
      if (value == true) {
        loadStudents();
      }
    });
  }

  void _showDeleteConfirmation() {
    // Count how many students have courses registered
    int studentsWithCourses = 0;
    for (final studentId in selectedStudentIds) {
      if ((studentCourses[studentId]?.isNotEmpty) ?? false) {
        studentsWithCourses++;
      }
    }

    String warningMessage =
        'Are you sure you want to delete the selected ${selectedStudentIds.length} student(s)?';

    if (studentsWithCourses > 0) {
      warningMessage +=
          '\n\nWARNING: $studentsWithCourses of these students have courses registered. Deleting them will also remove all their course registrations.';
    }

    warningMessage +=
        '\n\nNOTE: Students may have references in seating arrangements or other records that will also be deleted.';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Confirm Deletion',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.red.shade800,
          ),
        ),
        content: Text(
          warningMessage,
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ).then((value) async {
      if (value == true) {
        try {
          setState(() => isLoading = true);

          // First delete all seating arrangements for these students
          await Supabase.instance.client
              .from('seating_arr')
              .delete()
              .in_('student_reg_no', selectedStudentIds.toList());

          // Delete all course registrations for these students
          if (studentsWithCourses > 0) {
            await Supabase.instance.client
                .from('registered_students')
                .delete()
                .in_('student_reg_no', selectedStudentIds.toList());

            developer.log(
                'Deleted course registrations for ${selectedStudentIds.length} students');
          }

          // Then delete the students
          await Supabase.instance.client
              .from('student')
              .delete()
              .in_('student_reg_no', selectedStudentIds.toList());

          developer.log('Deleted ${selectedStudentIds.length} students');

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Successfully deleted ${selectedStudentIds.length} students'),
                backgroundColor: Colors.green,
              ),
            );
          }

          // Clear selection and reload data
          setState(() {
            selectedStudentIds.clear();
            selectAllChecked = false;
          });

          // Reload students
          loadStudents();
        } catch (error) {
          developer.log('Error deleting students: $error', error: error);
          if (mounted) {
            setState(() => isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to delete students: ${error.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    });
  }
}

class PreviewDialog extends StatelessWidget {
  final List<Map<String, dynamic>> students;
  final List<String> errors;

  const PreviewDialog({
    Key? key,
    required this.students,
    required this.errors,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final validCount = students.where((s) => !(s['has_error'] ?? false)).length;
    final errorCount = students.where((s) => s['has_error'] ?? false).length;

    return AlertDialog(
      title: const Text('Preview Import'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Found ${students.length} records:',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            Text(
              '$validCount valid, $errorCount with errors',
              style: GoogleFonts.poppins(
                color: errors.isEmpty ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            if (errors.isNotEmpty) ...[
              Text(
                'Errors:',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListView.builder(
                    itemCount: errors.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          errors[index],
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.red.shade800,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            Expanded(
              flex: 2,
              child: ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, index) {
                  final student = students[index];
                  final hasError = student['has_error'] ?? false;

                  return ListTile(
                    title: Text(
                      student['student_reg_no']?.toString() ?? 'No ID',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      student['student_name']?.toString() ?? 'No Name',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: hasError
                            ? Colors.red.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                    trailing: hasError
                        ? const Icon(Icons.error_outline, color: Colors.red)
                        : const Icon(Icons.check_circle_outline,
                            color: Colors.green),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: validCount > 0 ? () => Navigator.pop(context, true) : null,
          child: Text('Import $validCount Records'),
        ),
      ],
    );
  }
}

class AddStudentDialog extends StatefulWidget {
  const AddStudentDialog({Key? key}) : super(key: key);

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _regNoController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedDepartment;
  int? _selectedSemester;
  bool _isLoading = false;
  List<Map<String, dynamic>> _departments = [];
  final List<int> _semesters = [1, 2, 3, 4, 5, 6, 7, 8];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _regNoController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      setState(() => _isLoading = true);

      final response = await Supabase.instance.client
          .from('departments')
          .select('dept_id, dept_name')
          .order('dept_name');

      setState(() {
        _departments = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (error) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load departments: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _isLoading = true);

      await Supabase.instance.client.from('student').insert({
        'student_reg_no': _regNoController.text.trim().toUpperCase(),
        'student_name': _nameController.text.trim(),
        'dept_id': _selectedDepartment,
        'semester': _selectedSemester,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (error) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add student: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Student'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _regNoController,
                decoration: const InputDecoration(
                  labelText: 'Registration Number',
                  hintText: 'e.g., CSE1801',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter registration number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Student Name',
                  hintText: 'Full name',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter student name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                ),
                items: _departments.map((dept) {
                  return DropdownMenuItem<String>(
                    value: dept['dept_id'] as String,
                    child: Expanded(
                      child: Text('${dept['dept_id']} - ${dept['dept_name']}'),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedDepartment = value);
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a department';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedSemester,
                decoration: const InputDecoration(
                  labelText: 'Semester',
                ),
                items: _semesters.map((semester) {
                  return DropdownMenuItem<int>(
                    value: semester,
                    child: Text('Semester $semester'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedSemester = value);
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a semester';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _saveStudent,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
