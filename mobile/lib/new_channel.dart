import 'package:flutter/material.dart';

import 'api_service.dart';

class NewChannel extends StatefulWidget {
  NewChannel({Key key}) : super(key: key);

  @override
  _NewChannelState createState() => _NewChannelState();
}

class _NewChannelState extends State<NewChannel> {
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  Future _postMessage(BuildContext context) async {
    if (_messageController.text.length > 0) {
      await ApiService().createChannel(_messageController.text);
      Navigator.pop(context, true);
    } else {
      Scaffold.of(context).showSnackBar(
        SnackBar(
          content: Text('Please type a message'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Post Message"),
      ),
      body: Builder(
        builder: (context) {
          return Container(
            padding: EdgeInsets.all(12.0),
            child: Center(
              child: Column(
                children: [
                  TextField(
                    controller: _messageController,
                  ),
                  MaterialButton(
                    onPressed: () => _postMessage(context),
                    child: Text("Post"),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
