import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_attendance_system/models/attendance_model.dart';
import 'package:flutter_attendance_system/models/user_model.dart';
import 'package:flutter_attendance_system/viewmodel/auth_view_model.dart';
import 'package:flutter_attendance_system/viewmodel/time_date_view_model.dart';
import 'package:intl/intl.dart';

class AttendanceViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthViewModel authViewModel;
  final TimeDateViewModel timeDateViewModel;

  AttendanceViewModel(
      {required this.authViewModel, required this.timeDateViewModel});

  UserModel? _userModel;
  UserModel? get userModel => _userModel;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<UserAttendanceModel> _attendanceList = [];
  List<UserAttendanceModel> get attendanceList => _attendanceList;

  bool _isSuccessInOut = false;
  bool _isSuccessFetch = false;

  bool get isSuccessInOut => _isSuccessInOut;
  bool get isSuccessFetch => _isSuccessFetch;

  set isSuccessInOut(bool value) {
    _isSuccessInOut = value;
    notifyListeners();
  }

  DateTime? _checkInTime;
  DateTime? _checkOutTime;

  Future<void> timeIn() async {
    try {
      _checkInTime = DateTime.now();
      UserModel? userModel = authViewModel.userModel;
      if (userModel == null) {
        throw Exception("User not logged in");
      }

      QuerySnapshot attendanceQuery = await _firestore
          .collection('attendance')
          .where('user_id', isEqualTo: userModel.uid)
          .where('attendance_date',
              isEqualTo: DateFormat('yyyy-MM-dd').format(_checkInTime!))
          .get();

      if (attendanceQuery.docs.isNotEmpty) {
        throw Exception("You've already timed in today");
      }

      String lateTime = '';
      String attendanceStatus = '';
      DocumentSnapshot documentSnapshot =
          await _firestore.collection('users').doc(userModel.uid).get();
      if (documentSnapshot.exists) {
        Map<String, dynamic> data =
            documentSnapshot.data() as Map<String, dynamic>;
        String scheduleIn = data['schedule_in'];
        String timeIn = DateFormat('HH:mm:ss').format(_checkInTime!);
        DateTime scheduleInDateTime = DateFormat('HH:mm:ss').parse(scheduleIn);
        DateTime timeInDateTime = DateFormat('HH:mm:ss').parse(timeIn);
        if(timeInDateTime.isAfter(scheduleInDateTime)){
          lateTime = DateFormat('HH:mm:ss').format(
            DateTime(0).add(timeInDateTime.difference(scheduleInDateTime)));
        }
      }
      if(lateTime.isNotEmpty){
        attendanceStatus = 'Late';
      }

      UserAttendanceModel attendance = UserAttendanceModel(
        id: _firestore.collection('attendance').doc().id,
        userId: userModel.uid,
        userName: userModel.displayName,
        attendanceStatus: attendanceStatus,
        attendanceDate: DateFormat('yyyy-MM-dd').format(_checkInTime!),
        timeIn: DateFormat('HH:mm:ss').format(_checkInTime!),
        timeOut: '',
        totalTime: '',
        lateTime: lateTime,
        underTime: '',
      );
      await _firestore
          .collection('attendance')
          .doc(attendance.id)
          .set(attendance.toJson());
      _isSuccessInOut = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isSuccessInOut = false;
      notifyListeners();
    }
  }

  Future<Duration> _fetchBreakTimeDuration(String userId) async {
    DocumentSnapshot scheduleDoc =
        await _firestore.collection('users').doc(userId).get();
    if (scheduleDoc.exists) {
      Map<String, dynamic> scheduleData =
          scheduleDoc.data() as Map<String, dynamic>;
      String breakStartTime = scheduleData['break_start'];
      String breakEndTime = scheduleData['break_end'];

      DateTime breakStartDateTime =
          DateFormat('HH:mm:ss').parse(breakStartTime);
      DateTime breakEndDateTime = DateFormat('HH:mm:ss').parse(breakEndTime);

      return breakEndDateTime.difference(breakStartDateTime);
    } else {
      throw Exception("User schedule not found");
    }
  }

  Future<Duration> _fetchUserScheduledDuration(String userId) async {
    // Fetch the user's schedule from Firestore (assuming you have a 'schedules' collection)
    DocumentSnapshot scheduleDoc =
        await _firestore.collection('users').doc(userId).get();
    if (scheduleDoc.exists) {
      Map<String, dynamic> scheduleData =
          scheduleDoc.data() as Map<String, dynamic>;
      String startTime = scheduleData['schedule_in'];
      String endTime = scheduleData['schedule_out'];

      DateTime startDateTime = DateFormat('HH:mm:ss').parse(startTime);
      DateTime endDateTime = DateFormat('HH:mm:ss').parse(endTime);

      return endDateTime.difference(startDateTime);
    } else {
      throw Exception("User schedule not found");
    }
  }

  Future<void> timeOut() async {
    try {
      _checkOutTime = DateTime.now();
      UserModel? userModel = authViewModel.userModel;
      if (userModel == null) {
        throw Exception("User not logged in");
      }
      QuerySnapshot attendanceQuery = await _firestore
          .collection('attendance')
          .where('user_id', isEqualTo: userModel.uid)
          .where('attendance_date',
              isEqualTo: DateFormat('yyyy-MM-dd').format(_checkOutTime!))
          .get();
      if (attendanceQuery.docs.isNotEmpty) {
        DocumentSnapshot doc = attendanceQuery.docs.first;
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data['time_out'] != null && data['time_out'].isNotEmpty) {
          throw Exception("You've already timed out today");
        }
        await _firestore.collection('attendance').doc(doc.id).update({
          'time_out': DateFormat('HH:mm:ss').format(_checkOutTime!),
        });

        // Calculate hours worked
        DateTime timeIn = DateFormat('HH:mm:ss').parse(data['time_in']);
        DateTime timeOut = DateFormat('HH:mm:ss')
            .parse(DateFormat('HH:mm:ss').format(_checkOutTime!));
        Duration workedDuration = timeOut.difference(timeIn);

        // Fetch user's schedule (assuming you have a method to get the user's schedule)
        Duration scheduledDuration =
            await _fetchUserScheduledDuration(userModel.uid);

        // Update the attendance record with the worked hours
        String adjustedWorkedDurationFormatted =
            getAdjustedWorkedDurationFormatted(workedDuration);
        await _firestore.collection('attendance').doc(doc.id).update({
          'total_time': adjustedWorkedDurationFormatted,
        });

        DocumentSnapshot documentSnapshot =
            await _firestore.collection('users').doc(userModel.uid).get();
        Map<String, dynamic> userData =
            documentSnapshot.data() as Map<String, dynamic>;
        String scheduleOut = userData['schedule_out'];
        String stringTimeout = DateFormat('HH:mm:ss').format(_checkOutTime!);
        DateTime scheduleOutDateTime =
            DateFormat('HH:mm:ss').parse(scheduleOut);
        DateTime timeOutDateTime = DateFormat('HH:mm:ss').parse(stringTimeout);
        if (timeOutDateTime.isBefore(scheduleOutDateTime)) {
          String underTime = '';
          Duration durationOfUnderTime =
              scheduleOutDateTime.difference(timeOutDateTime);
          underTime = DateFormat('HH:mm:ss')
              .format(DateTime(0).add(durationOfUnderTime));
          await _firestore.collection('attendance').doc(doc.id).update({
            'under_time': underTime,
          });
        }

        //Condition to check if the user is present
        // if ((workedDuration > scheduledDuration) &&
        //     data['under_time'].isEmpty &&
        //     data['late_time'].isEmpty) {
        //   await _firestore.collection('attendance').doc(doc.id).update({
        //     'attendance_status': 'Present',
        //   });
        // } else if (data['late_time'].isNotEmpty &&
        //     data['under_time'].isNotEmpty) {
        //   await _firestore.collection('attendance').doc(doc.id).update({
        //     'attendance_status':
        //         getAdjustedWorkedDurationFormatted(workedDuration),
        //   });
        // } else if (data['late_time'].isNotEmpty) {
        //   await _firestore.collection('attendance').doc(doc.id).update({
        //     'attendance_status': 'Late',
        //   });
        // } else if (data['under_time'].isNotEmpty) {
        //   await _firestore.collection('attendance').doc(doc.id).update({
        //     'attendance_status': 'UnderTime',
        //   });
        // } else {
        //   await _firestore.collection('attendance').doc(doc.id).update({
        //     'attendance_status': 'Absent',
        //   });
        // }

        _isSuccessInOut = true;
        notifyListeners();
      } else {
        throw Exception("Time in not recorded");
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isSuccessInOut = false;
      notifyListeners();
    }
  }

  String timeStatus(
    Duration workedDuration,
    Duration scheduledDuration,
  ) {
    if (workedDuration > scheduledDuration) {
      return 'Present';
    } else if (workedDuration < scheduledDuration) {
      return 'Absent';
    } else {
      return 'On Time';
    }
  }

  String getAdjustedWorkedDurationFormatted(Duration _adjustedWorkedDuration) {
    if (_adjustedWorkedDuration != null) {
      int hours = _adjustedWorkedDuration!.inHours;
      int minutes = _adjustedWorkedDuration!.inMinutes.remainder(60);
      int seconds = _adjustedWorkedDuration!.inSeconds.remainder(60);
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '00:00';
  }

  Duration stringToDuration(String durationString) {
    List<String> parts = durationString.split(':');
    if (parts.length == 3) {
      int hours = int.parse(parts[0]);
      int minutes = int.parse(parts[1]);
      int seconds = int.parse(parts[2]);
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    } else if (parts.length == 2) {
      int hours = int.parse(parts[0]);
      int minutes = int.parse(parts[1]);
      return Duration(hours: hours, minutes: minutes);
    } else {
      return Duration.zero;
    }
  }

  Map<String, int> getDurationComponents(String durationString) {
    Duration duration = stringToDuration(durationString);
    int hours = duration.inHours;
    int minutes = duration.inMinutes.remainder(60);
    int seconds = duration.inSeconds.remainder(60);
    return {
      'hours': hours,
      'minutes': minutes,
      'seconds': seconds,
    };
  }

  Future<void> fetchUserAttendance(DateTime date) async {
    try {
      UserModel? userModel = authViewModel.userModel;
      if (userModel == null) {
        throw Exception("User not logged in");
      }
      String formattedDate = DateFormat('yyyy-MM-dd').format(date);
      QuerySnapshot attendanceQuery = await _firestore
          .collection('attendance')
          .where('user_id', isEqualTo: userModel.uid)
          .where('attendance_date', isEqualTo: formattedDate)
          .orderBy('attendance_date', descending: true)
          .get();
      _attendanceList = attendanceQuery.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return UserAttendanceModel.fromJson(data);
      }).toList();
      notifyListeners();
      _isSuccessFetch = true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<List<UserAttendanceModel>> fetchAllUserAttendanceByYearAndMonth(
      int year, int month, int cutoffs) async {
    try {
      List<UserAttendanceModel> attendanceListByYearAndMonth = [];
      UserModel? userModel = authViewModel.userModel;
      if (userModel == null) {
        throw Exception("User not logged in");
      }
      DateTime startDate = cutoffs == 15
          ? DateTime(year, month, 1)
          : DateTime(year, month, 16); // Start date of the month
      DateTime endDate = cutoffs == 15
          ? DateTime(year, month, 15)
          : DateTime(year, month + 1, 0); // Last day of the month
      QuerySnapshot attendanceQuery = await _firestore
          .collection('attendance')
          .where('user_id', isEqualTo: userModel.uid)
          .where('attendance_date',
              isGreaterThanOrEqualTo:
                  DateFormat('yyyy-MM-dd').format(startDate))
          .where('attendance_date',
              isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(endDate))
          .orderBy('attendance_date', descending: true)
          .get();
      attendanceListByYearAndMonth = attendanceQuery.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return UserAttendanceModel.fromJson(data);
      }).toList();
      return attendanceListByYearAndMonth;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return [];
    }
  }

  String statusMessage() {
    if (_attendanceList.isNotEmpty) {
      String? timeIn = _attendanceList.first.timeIn;
      String? timeOut = _attendanceList.first.timeOut;
      if ((timeIn != null && timeIn.isNotEmpty) &&
          (timeOut == null || timeOut.isEmpty)) {
        return 'You have timed in today, Pending time out...';
      } else if ((timeIn != null && timeIn.isNotEmpty) &&
          (timeOut != null && timeOut.isNotEmpty)) {
        return 'You have timed in and out today';
      }
    }
    return 'You have not yet timed in today';
  }

  // Method to get the latest time in and convert it to 12-hour format
  String getLatestTimeIn() {
    if (_attendanceList.isNotEmpty) {
      String? timeIn = _attendanceList.first.timeIn;
      if (timeIn != null && timeIn.isNotEmpty) {
        DateTime parsedTime = DateFormat('HH:mm:ss').parse(timeIn);
        return DateFormat('hh:mm:ss a').format(parsedTime);
      }
    }
    return 'Pending time in...';
  }

  // Method to get the latest time out and convert it to 12-hour format
  String getLatestTimeOut() {
    if (_attendanceList.isNotEmpty) {
      String? timeOut = _attendanceList.first.timeOut;
      if (timeOut != null && timeOut.isNotEmpty) {
        DateTime parsedTime = DateFormat('HH:mm:ss').parse(timeOut);
        return DateFormat('hh:mm:ss a').format(parsedTime);
      }
    }
    return 'Pending time out...';
  }
}
