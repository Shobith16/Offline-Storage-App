import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('uploads'); // Box for storing uploads
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Upload Speed Monitor',
      home: UploadScreen(),
    );
  }
}

class UploadScreen extends StatefulWidget {
  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  late Box uploadsBox;



  List<dynamic> records = []; // To hold records for display
  //
  @override
  void initState() {
    super.initState();
    uploadsBox = Hive.box('uploads');
    _loadRecords(); // Load records when the app starts
    _checkInitialConnection();

    // Update subscription to listen for connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> result) {
      if (result.isNotEmpty) {
        _updateConnectionStatus(result.first); // Use the first result
      }
    });
  }

  Future<void> _checkInitialConnection() async {
    var result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result.first);
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    setState(() {
      _connectionStatus = result;
    });

    // Attempt to upload any stored data when connection is restored
    if (_connectionStatus != ConnectivityResult.none) {
      await _uploadStoredData();
    }
  }

  Future<void> uploadData(Uint8List data, Map<String, dynamic> userData) async {
    final stopwatch = Stopwatch()..start();

    try {
      var headers = {
        'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2NjE3Njg1ZGI5ZDRjZjQyMTg3MzA5MjMiLCJpYXQiOjE3MjcxNzg2NTIsImV4cCI6MTcyNzUzODY1Mn0.FkcBmHAFytCCQTPPr-jYO428-obeGuVN-5BRxJzmQkg', // Replace with your actual token
      };

      var request = http.MultipartRequest(
          'POST',
          Uri.parse('https://safegate.informerio.com/safegate/api/activity/upload'));

      request.files.add(http.MultipartFile.fromBytes(
        'image',
        data,
        filename: 'uploaded_image.png',
        contentType: MediaType('image', 'png'),
      ));

      request.headers.addAll(headers);

      // Use Future.timeout to limit upload time to 15 seconds
      http.StreamedResponse response = await request.send().timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        print(await response.stream.bytesToString());
        print('Upload successful');
      } else {
        print(response.reasonPhrase);
        print('Upload failed, storing locally');

        bool exists = await checkIfExists(userData);
        if (!exists) {
          await uploadsBox.add({
            'data': userData,
            'image': data, // Store the image as Uint8List
          });
          print('Data stored locally.');
        } else {
          print('Data already exists in local storage.');
        }
      }
    } catch (e) {
      bool exists = await checkIfExists(userData);
      if (!exists) {
        await uploadsBox.add({
          'data': userData,
          'image': data, // Store the image as Uint8List
        });
      }
        print('Data stored locally.');
      if (e is TimeoutException) {
        print('Upload exceeded 15 seconds');
      } else {
        print('Error during upload: $e');
      }
    } finally {
      stopwatch.stop();
      print('Elapsed time: ${stopwatch.elapsed.inSeconds} seconds');
      _loadRecords(); // Refresh records after upload attempt
    }
  }

  Future<bool> checkIfExists(Map<String, dynamic> userData) async {
    for (int i = 0; i < uploadsBox.length; i++) {
      final storedData = uploadsBox.getAt(i);

      // Check for unique identifier (e.g., phone number or email)
      if (storedData['data']['phone'] == userData['phone'] ||
          storedData['data']['email'] == userData['email']) {
        return true; // Data already exists
      }
    }
    return false; // Data does not exist
  }

  Future<void> _uploadStoredData() async {
    for (int i = uploadsBox.length - 1; i >= 0; i--) { // Iterate backwards to avoid index issues after removal
      final storedData = uploadsBox.getAt(i);
      // final storedData = uploadsBox.get('data');

      // Ensure proper casting of stored data
      Map<String, dynamic> userData = Map<String, dynamic>.from(storedData['data']);
      Uint8List imageData = storedData['image'];

      // Attempt to upload stored data
      await uploadData(imageData, userData);

      // Remove from local storage after successful upload
      await uploadsBox.deleteAt(i);
    }
  }

  void _loadRecords() {
    setState(() {
      records = uploadsBox.values.toList(); // Load all records from the box
    });
  }

  List<Widget> _buildRecordList() {
    List<Widget> recordWidgets = [];

    if (records.isEmpty) {
      recordWidgets.add(
        Center(child: Text('No Records', style: TextStyle(fontSize: 20))),
      );
    } else {
      for (var record in records) {
        Map<String, dynamic> userData = Map<String, dynamic>.from(record['data']);
        Uint8List imageData = record['image'];

        recordWidgets.add(
          ListTile(
            title: Text(userData['name']),
            subtitle: Text('Phone: ${userData['phone']}, Age: ${userData['age']}, Email: ${userData['email']}'),
            leading: Image.memory(imageData, width: 50, height: 50), // Display image thumbnail
          ),
        );
      }
    }

    return recordWidgets;
  }

  @override
  void dispose() {
    _subscription.cancel(); // Cancel subscription on dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Upload Speed Monitor')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: _buildRecordList(),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Current Connection Status: ${_connectionStatus.toString()}',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Pick an image file from the device using FilePicker
          FilePickerResult? result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            allowCompression: false,
            withData: true,
          );

          if (result != null && result.files.isNotEmpty) {
            PlatformFile file = result.files.first;

            print('Selected file: ${file.name}');
            print('File path: ${file.path}');
            print('File size: ${file.size}');

            // Ensure file.bytes is not null before using it
            if (file.bytes != null) {
              Map<String, dynamic> userData = {
                'name': 'John Doe',
                'phone': '1234567832',
                'age': 30,
                'email': 'johndoe4@example.com'
              };

              await uploadData(file.bytes!, userData); // Call upload function with picked bytes.
            } else {
              print("File bytes are null.");
            }
          } else {
            print("User cancelled the picker or no files were selected.");
          }
        },
        child: Icon(Icons.upload),
      ),
    );
  }
}