import 'package:flutter/material.dart';
import '../models/period_model.dart';

class PeriodEditorScreen extends StatefulWidget {

  final PeriodModel period;

  const PeriodEditorScreen({
    super.key,
    required this.period,
  });

  @override
  State<PeriodEditorScreen> createState() =>
      _PeriodEditorScreenState();
}

class _PeriodEditorScreenState
    extends State<PeriodEditorScreen> {

  final _formKey = GlobalKey<FormState>();

  late TextEditingController roomController;

  late TextEditingController notesController;

  String? selectedSubject;

  String? selectedFaculty;

  String classType = "Theory";

  bool isFree = false;

  @override
  void initState() {
    super.initState();

    selectedSubject = widget.period.subject;

    selectedFaculty = widget.period.facultyName;

    roomController =
        TextEditingController(text: widget.period.room);

    notesController = TextEditingController();

    if (widget.period.isFree) {
      classType = "Free";
      isFree = true;
    }
  }

  @override
  void dispose() {
    roomController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("Edit Period"),
      ),

      body: Form(

        key: _formKey,

        child: ListView(

          padding: const EdgeInsets.all(20),

          children: [

            Text(
              "${widget.period.startTime} - ${widget.period.endTime}",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 30),

            DropdownButtonFormField<String>(

              initialValue: selectedSubject,

              decoration: const InputDecoration(
                labelText: "Subject",
              ),

              items: const [

                DropdownMenuItem(
                  value: "Power Electronics",
                  child: Text("Power Electronics"),
                ),

                DropdownMenuItem(
                  value: "Control Systems",
                  child: Text("Control Systems"),
                ),

                DropdownMenuItem(
                  value: "DSP",
                  child: Text("Digital Signal Processing"),
                ),

                DropdownMenuItem(
                  value: "Machine Design",
                  child: Text("Machine Design"),
                ),

              ],

              onChanged: isFree
                  ? null
                  : (value) {
                      setState(() {
                        selectedSubject = value;
                      });
                    },

            ),

            const SizedBox(height: 20),

            DropdownButtonFormField<String>(

              initialValue: selectedFaculty,

              decoration: const InputDecoration(
                labelText: "Faculty",
              ),

              items: const [

                DropdownMenuItem(
                  value: "Dr. Srinivas",
                  child: Text("Dr. Srinivas"),
                ),

                DropdownMenuItem(
                  value: "Dr. Kumar",
                  child: Text("Dr. Kumar"),
                ),

                DropdownMenuItem(
                  value: "Dr. Rao",
                  child: Text("Dr. Rao"),
                ),

              ],

              onChanged: isFree
                  ? null
                  : (value) {
                      setState(() {
                        selectedFaculty = value;
                      });
                    },

            ),

            const SizedBox(height: 20),

            TextFormField(

              controller: roomController,

              enabled: !isFree,

              decoration: const InputDecoration(
                labelText: "Room",
              ),

            ),

            const SizedBox(height: 25),

            const Text(
              "Class Type",
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            RadioGroup<String>(
              groupValue: classType,
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  classType = v;
                  isFree = v == "Free";
                });
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: "Theory",
                    title: const Text("Theory"),
                  ),
                  RadioListTile<String>(
                    value: "Lab",
                    title: const Text("Laboratory"),
                  ),
                  RadioListTile<String>(
                    value: "Tutorial",
                    title: const Text("Tutorial"),
                  ),
                  RadioListTile<String>(
                    value: "Free",
                    title: const Text("Free Period"),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            TextFormField(

              controller: notesController,

              maxLines: 4,

              decoration: const InputDecoration(

                labelText: "Notes",

                border: OutlineInputBorder(),

              ),

            ),

            const SizedBox(height: 40),

            SizedBox(

              height: 55,

              child: FilledButton(

                onPressed: () {

                  /// save

                },

                child: const Text(
                  "Save Period",
                ),

              ),

            ),

          ],

        ),

      ),

    );

  }

}