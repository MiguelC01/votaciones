import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:votaciones/main.dart';
import 'create_survey.dart';
import 'survey_history.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PublishedSurveysScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Encuestas Publicadas'),
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('surveys')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No hay encuestas publicadas.'));
          }

          return ListView(
            children: snapshot.data!.docs.map((doc) {
              var survey = doc.data() as Map<String, dynamic>;
              return SurveyTile(doc: doc);
            }).toList(),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "createSurvey",
            tooltip: "Nueva publicación",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => CreateSurveyScreen()),
              );
            },
            child: Icon(Icons.add),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "surveyHistory",
            tooltip: "Mis publicaciones",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => SurveyHistoryScreen()),
              );
            },
            child: Icon(Icons.history),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "logout",
            tooltip: "Cerrar sesión",
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => AuthScreen()),
              );
            },
            child: Icon(Icons.exit_to_app),
          ),
        ],
      ),
    );
  }
}

class SurveyTile extends StatefulWidget {
  final QueryDocumentSnapshot doc;

  SurveyTile({required this.doc});

  @override
  _SurveyTileState createState() => _SurveyTileState();
}

class _SurveyTileState extends State<SurveyTile> {
  String? _selectedOption;
  bool _hasVoted = false;

  @override
  void initState() {
    super.initState();
    _checkIfUserHasVoted();
  }

  void _checkIfUserHasVoted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var survey = widget.doc.data() as Map<String, dynamic>;
      var votes = (survey['votes'] as Map<String, dynamic>?) ?? {};
      if (votes.containsKey(user.uid)) {
        setState(() {
          _selectedOption = votes[user.uid];
          _hasVoted = true;
        });
      }
    }
  }

  String getTimeRemaining(DateTime expiresAt) {
    final now = DateTime.now();
    final difference = expiresAt.difference(now);
    if (difference.isNegative) {
      return 'La encuesta ha caducado.';
    }

    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;
    return 'Tiempo restante: $hours horas $minutes minutos';
  }

  @override
  Widget build(BuildContext context) {
    var survey = widget.doc.data() as Map<String, dynamic>;
    var options = (survey['options'] as List<dynamic>).cast<String>();
    var votes = (survey['votes'] as Map<String, dynamic>?) ?? {};
    var expiresAt = DateTime.parse(survey['expires_at']);
    var now = DateTime.now();
    var isExpired = now.isAfter(expiresAt);

    return Card(
      margin: EdgeInsets.all(8.0),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              survey['question'],
              style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            if (!isExpired)
              ...options.map((option) {
                return RadioListTile<String>(
                  title: Text(option),
                  value: option,
                  groupValue: _selectedOption,
                  onChanged: (value) {
                    setState(() {
                      _selectedOption = value;
                    });
                  },
                );
              }).toList(),
            if (!isExpired)
              ElevatedButton(
                onPressed: _selectedOption == null
                    ? null
                    : () async {
                        if (_selectedOption != null) {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            await FirebaseFirestore.instance
                                .runTransaction((transaction) async {
                              DocumentSnapshot freshSnap =
                                  await transaction.get(widget.doc.reference);
                              var freshData =
                                  freshSnap.data() as Map<String, dynamic>;
                              var freshVotes = (freshData['votes']
                                      as Map<String, dynamic>?) ??
                                  {};
                              freshVotes[user.uid] = _selectedOption;

                              transaction.update(
                                  widget.doc.reference, {'votes': freshVotes});
                            });
                            setState(() {
                              _hasVoted = true;
                            });
                          }
                        }
                      },
                child: Text('Votar'),
              ),
            SizedBox(height: 10),
            Text(
              'Resultados:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: options.map((option) {
                int voteCount =
                    votes.values.where((vote) => vote == option).length;
                return Text('$option: $voteCount votos');
              }).toList(),
            ),
            SizedBox(height: 10),
            Text(
              getTimeRemaining(expiresAt),
              style: TextStyle(color: isExpired ? Colors.red : Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}
