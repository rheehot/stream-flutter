# Stream Flutter: Building a Social Network with Stream and Flutter
## Part 2: Direct Messaging

In the second part of our series, we'll implement direct messaging between users by integrating [Stream Chat](https://getstream.io/chat/). This post assumes you've followed along with [part 1](https://github.com/nparsons08/stream-flutter/tree/1-social). 

## Building Stream Flutter: Direct Messaging

Leveraging our code from part 1, we'll modify the backend to create a Stream Chat frontend token and do the rest of our work in the mobile application. The Stream Chat frontend token securely authenticates a client application with the Stream Chat so it can directly talk with the API without going through our backend. This token is created and stored as a part of the login process which is defined in part 1.

For the backend, we'll add in the [Stream Chat JavaScript](https://www.npmjs.com/package/stream-chat) library. 

For the mobile app, we'll build it with Flutter wrapping the Stream Chat [Android](https://github.com/GetStream/stream-chat-android) and [Swift](https://github.com/GetStream/stream-chat-swift) libraries.

The app goes through these steps to allow a user to chat with another:

* User navigates to the user list, selects a user, and clicks "Chat". The mobile application joins a 1-on-1 chat channel between the two users.
* The app queries the channel for previous messages and indicates to Stream that we'd like to watch this channel for new messages. The mobile app listens for new messages.
* The user creates a new message and sends it to the Stream API. 
* When the message is created, or a message from the other user is received, the mobile application consumes the event and displays the message.

Since we're relying on the Stream mobile libraries to do the heavy lifting, such as creating a websocket connection with the Stream API, this process is a dance between the Flutter code and native (Swift/Kotlin) via [Platform Channels](https://flutter.dev/docs/development/platform-integration/platform-channels). If you'd like to follow along , make sure you get both the backend and mobile app running part 1 before continuing.

## Prerequisites

Basic knowledge of [Node.js](https://nodejs.org/en/) (JavaScript), [Flutter](https://flutter.dev/) ([Dart](https://dart.dev/)), and [Kotlin](https://kotlinlang.org/), is required to follow this tutorial. Knowledge of Swift is useful if you want to browse the iOS impelementation. This code is intended to run locally on your machine. 

If you'd like to follow along, you'll need an account with [Stream](https://getstream.io/accounts/signup/). Please make sure you can run a Flutter app, at least on Android. If you haven't done so, make sure you have Flutter [installed](https://flutter.dev/docs/get-started/install). If you're having issues building this project, please check if you can create run a simple application by following the instructions [here](https://flutter.dev/docs/get-started/test-drive).

Once you have an account with Stream, you need to set up a development app (see part 1):

![](images/create-app.png)

You'll need to add the credentials from the Stream app to the source code for it to work. See both the `mobile` and `backend` READMEs. 

Let's get to building!


## User sends a message

### Step 1: Get Stream Chat frontend token

To communicate with the Stream Chat API from our mobile app, we need an authenticated frontend token. To get this, we'll add a step into our login process that requests this token, essentially replicating how we received our Stream Activity Feed API frontend token. First, in Flutter, we add a step to the login that requests this token be generated by the `backend`:

```dart
// mobile/lib/api_service.dart:16
Future<Map> login(String user) async {
  var authResponse = await http.post('$_baseUrl/v1/users', body: {'sender': user});
  var authToken = json.decode(authResponse.body)['authToken'];
  var feedResponse =
      await http.post('$_baseUrl/v1/stream-feed-credentials', headers: {'Authorization': 'Bearer $authToken'});
  var feedToken = json.decode(feedResponse.body)['token'];
  var chatResponse =
      await http.post('$_baseUrl/v1/stream-chat-credentials', headers: {'Authorization': 'Bearer $authToken'});
  var chatToken = json.decode(chatResponse.body)['token'];
  await platform.invokeMethod('setupChat', {'user': user, 'token': chatToken});

  return {'authToken': authToken, 'feedToken': feedToken, 'chatToken': chatToken};
}
```

This is identical to part 1's login flow except for the `chatToken` creation and `setupChat`. Here we hit a separate `backend` endpoint `/v1/stream-chat-credentials` to generate the token. Let's look at how the backend is implemented:

Once we've received the token we can set up our chat objects by telling the native code to `setupChat`. Here is what's happening on the Android side:

```kotlin
// mobile/android/app/src/main/kotlin/io/getstream/flutter_the_stream/MainActivity.kt:95
private fun setupChat(user: String, token: String) {
  StreamChat.init(API_KEY, applicationContext)
  val client = StreamChat.getInstance(this.application)
  client.setUser(User(user), token)
}
```

Here we're initializing the `StreamChat` singleton with our `API_KEY`. We set the user on this instance so Stream knows who's talking to the API and how to authenticate them. This sets up future calls to this library to leverage this instance.

```javascript
// backend/src/controllers/v1/stream-chat-credentials/stream-chat-credentials.action.js:6
exports.streamChatCredentials = async (req, res) => {
  try {
    const data = req.body;
    const apiKey = process.env.STREAM_API_KEY;
    const apiSecret = process.env.STREAM_API_SECRET;

    const client = new StreamChat(apiKey, apiSecret);

    const user = Object.assign({}, data, {
      id: req.user.sender,
      role: 'admin',
      image: `https://robohash.org/${req.user.sender}`,
    });
    const token = client.createToken(user.id);
    await client.updateUsers([user]);

    res.status(200).json({ user, token, apiKey });
  } catch (error) {
    console.log(error);
    res.status(500).json({ error: error.message });
  }
};
```

Here we use the same API credentials as the feed endpoint but use them to create a `StreamChat` instance. Using this object we can create a token and update that user in Stream. We return this data to the mobile app so it can store it for use

### Step 2: Start a chat

Once we have our token the user can navigate to the user list and indicate which user they'd like to start a chat with. To do this we'll add a new button next to "Follow" that starts the chat.

![](images/start-chat.png)

Let's look at how we add this button to this dialog:

```dart
// mobile/lib/people.dart:51
FlatButton(
  child: const Text('Chat'),
  onPressed: () {
    Navigator.pop(context); // close dialog
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Chat(account: widget.account, user: user)),
    );
  },
)
```

Since we already have our dialog built, this is relatively straightforward. We simply create a `FlatButton` that pushes a `Chat` widget onto the navigation stack.

### Step 3: Sending a message

First, we need to create a basic layout that will display our chat messages and our input. The view looks like this:

![](images/chat-empty.png)

And the Flutter code that produces this:

```dart
// mobile/lib/chat.dart:129
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text("Chat with ${widget.user}"),
    ),
    body: Builder(
      builder: (context) {
        if (_messages == null) {
          return Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            buildMessages(_messages),
            buildInput(context),
          ],
        );
      },
    ),
  );
}
```

Here we use a simple `Scaffold` layout to give us an `AppBar` with a back button to exit the chat. If the `_messages` variable is null, which it will be on load, we'll display a loading spinner. Once the initial messages are loaded, we show the chat widgets. For now, we're going to focus on sending a message.  We'll explore how messages are loaded and displayed later.

Next, let's define `buildInput` which creates the new message input widget:

```dart
// mobile/lib/chat.dart:81
Widget buildInput(BuildContext context) {
  return Container(
    margin: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
    child: Row(
      children: <Widget>[
        // Edit text
        Flexible(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              style: TextStyle(fontSize: 15.0),
              controller: _messageController,
              decoration: InputDecoration.collapsed(
                hintText: 'Type your message...',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ),

        // Button send message
        Material(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 8.0),
            child: IconButton(
              icon: Icon(Icons.send),
              onPressed: _postMessage,
            ),
          ),
          color: Colors.white,
        ),
      ],
    ),
    width: double.infinity,
    height: 50.0,
    decoration:
        BoxDecoration(border: Border(top: BorderSide(color: Colors.blueGrey, width: 0.5)), color: Colors.white),
  );
}
```

This is a `Container` that is a `Row` containing the message input and send button. The message input is `Flexible` meaning it will take up any remaining space in the `Row` not taken by the other widgets, in this case, the send button. The input is bound to `_messageController` which is a `TextEditingController`. This stores whatever is typed in. 

When a user is ready to send the message, they will press the send button which triggers `_postMessage`:

```dart
// mobile/lib/chat.dart:44
Future _postMessage() async {
  if (_messageController.text.length > 0) {
    await ApiService().postChatMessage(widget.account, widget.user, _messageController.text);
    _messageController.clear();
  }
}
```

If there's a message present, we take the text and send it to the native code with the account and user that is sending the message. Once that's done, we clear the text to ready it for the next message.

Let's take a look at what's happening in `ApiService`:

```dart
// mobile/lib/api_service.dart:63
Future<bool> postChatMessage(Map account, String userToChatWith, String message) async {
  await platform.invokeMethod('postChatMessage',
      {'user': account['user'], 'userToChatWith': userToChatWith, 'message': message, 'token': account['chatToken']});
  return true;
}
```

We simply send this message, along with the `chatToken` created during login, to the native side. The native side is where we interact with Stream to send the message:

```kotlin
// mobile/android/app/src/main/kotlin/io/getstream/flutter_the_stream/MainActivity.kt:180
private fun postChatMessage(result: MethodChannel.Result, user: String, userToChatWith: String, message: String, token: String) {
  val client = StreamChat.getInstance(this.application)
  val channel = client.channel("messaging", listOf(user, userToChatWith).sorted().joinToString("-"))
  val streamMessage = Message()
  streamMessage.text = message
  channel.sendMessage(streamMessage, object : MessageCallback {
    override fun onSuccess(response: MessageResponse?) {
      result.success(true)
    }

    override fun onError(errMsg: String?, errCode: Int) {
      result.error("FAILURE", errMsg, null)
    }
  })
}
```

We start by grabbing the `StreamChat` instance that we created during login via `setupChat`. We connect to our channel, which is a `messaging` channel [type](https://getstream.io/chat/docs/initialize_channel/?language=js#channel_initialization_parameters). The channel id is the two user's ids sorted and joined together with `-`. So if we're `sara` chatting with `jeff` our channel id is `jeff-sara`. Using a unique, consistent id is important so our users are joining the correct channels!

Once we've got the correct channel initialized, we create a Stream `Message` add the text and send it to the channel. Stream is smart enough to lazily create the channel if it does not exist when we send our first message. On success, we simply respond true. We could choose to send the message back to the Flutter side for display, but since we're listening to the Stream websocket for new messages, we'll see our new message come across there. We'll explore how this is done next.

## User views messages

### Step 1: Streaming messages

When we boot the chat widget, we want to grab the initial messages from the channel. We'll store this in an instance variable that is initialized in `initState`:

```dart
// mobile/lib/chat.dart:20
@override
void initState() {
  _setupChannel();
  super.initState();
}

// mobile/lib/chat.dart:32
Future _setupChannel() async {
  cancelChannel = await ApiService().listenToChannel(widget.account, widget.user, (messages) {
    setState(() {
      var prevMessages = [];
      if (_messages != null) {
        prevMessages = _messages;
      }
      _messages = prevMessages + messages;
    });
  });
}
```

Here we call the `ApiService` to start a connection with the channel. The `listenToChannel` method will first query the historical messages and send them along to our callback. Whenever a new set of messages is generated. This happens whenever either user creates a message. 

This widget responds to new messages by setting a new state by merging the previously displayed messages with any new messages that have been sent along. 

This stream is open until we explicitly cancel the channel connection. The `listenToChannel` method returns a cancel function. We store this and call it when we dispose the widget:

```dart
// mobile/lib/chat.dart:26
@override
void dispose() {
  cancelChannel();
  super.dispose();
}
```

Let's look at how we implement the `listenToChannel` method:

```dart
// mobile/lib/api_service.dart:69
Future<CancelListening> listenToChannel(Map account, String userToChatWith, Listener listener) async {
  var channelId = await platform.invokeMethod<String>(
      'setupChannel', {'user': account['user'], 'userToChatWith': userToChatWith, 'token': account['chatToken']});
  var subscription = EventChannel('io.getstream/events/$channelId').receiveBroadcastStream(nextListenerId++).listen(
    (results) {
      listener(json.decode(results));
    },
    cancelOnError: true,
  );

  return () {
    subscription.cancel();
  };
}
```

First, we call the native side to set up the channel. We'll look at this in a second but it essentially starts the websocket connection with Stream's API and returns the channel id. Using this channel id, we bind to a Flutter [EventChannel](https://api.flutter.dev/flutter/services/EventChannel-class.html). This class allows us to build an event bus between the native code and our flutter code. We bind to the broadcast stream under that channel id and start it by calling `listen`. The native code will stream messages to this code that's in a JSON string format. We decode the results and pass them along to the `listener` callback given to this method. 

For the caller code to tell us when to cancel this subscription, we return a small void function which wraps our `subscription.cancel` call.

Now we go to the native Android implementation of `setupChannel` to see how we start a streaming connection with Stream.

```kotlin
// mobile/android/app/src/main/kotlin/io/getstream/flutter_the_stream/MainActivity.kt:135
private fun setupChannel(result: MethodChannel.Result, user: String, userToChatWith: String, token: String) {
  val application = this.application
  val channelId = listOf(user, userToChatWith).sorted().joinToString("-")
  var subId : Int? = null
  val client = StreamChat.getInstance(application)
  val channel = client.channel("messaging", channelId)
  val eventChannel = EventChannel(flutterView, "io.getstream/events/${channelId}")

  eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
    override fun onListen(listener: Any, eventSink: EventChannel.EventSink) {
      channel.watch(ChannelWatchRequest(), object : QueryWatchCallback {
        override fun onSuccess(response: ChannelState) {
          eventSink.success(ObjectMapper().writeValueAsString(response.messages))
        }

        override fun onError(errMsg: String, errCode: Int) {
          eventSink.error(errCode.toString(), errMsg, null)
        }
      })

      subId = channel.addEventHandler(object : ChatChannelEventHandler() {
        override fun onMessageNew(event: Event) {
          eventSink.success(ObjectMapper().writeValueAsString(listOf(event.message)))
        }
      })
    }

    override fun onCancel(listener: Any) {
      channel.stopWatching(object : CompletableCallback {
        override fun onSuccess(response: CompletableResponse?) {
        }

        override fun onError(errMsg: String?, errCode: Int) {
          // handle errors
        }
      })
      channel.removeEventHandler(subId)
      eventChannels.remove(channelId)
    }
  })

  eventChannels[channelId] = eventChannel

  result.success(channelId)
}
```

A lot is going on here, but we'll walk through it step by step. Essentially, this function does four things: 

1) Setup a Flutter Java [EventChannel](https://api.flutter.dev/javadoc/io/flutter/plugin/common/EventChannel.html).
2) Tells Stream that we're going to watch this channel (meaning we start a websocket connection) and sends the first page of messages to the event sink.
3) Binds to the channel's new messages event stream and sends them to the event sink.
4) Handles when the user cancels this stream and cleans everything up.

Walking through the code, the first thing the code does is sets up the channel with the correct `channelId` using our `StreamChat` singleton. We then build our Flutter `EventChannel` using that `channelId` so we can stream messages (events) back to the dart side. We store this in a map so we can later unbind our event listeners.

To keep things all in one place, the code uses [object expressions](https://kotlinlang.org/docs/reference/object-declarations.html) to instantiate objects of an anonymous class.

The call to `setStreamHandler` takes an object that implements `EventChannel.StreamHandler`. This requires two callback methods `onListen` and `onCancel`. `onListen` happens when the `EventChannel` is listened to, which happens on the dart side (shown above). `onCancel` is called when the listener tells us to stop (also shown above in dart).

Looking at the `onListen` method, we see this is where we tell the channel we'd like to watch it. This method does two things. First, it informs Stream that we're going to bind to the channel and listen for any new messages. It also queries the last set of messages and calls our `QueryWatchCallback` object's method `onSuccess` with those messages. We send these messages along to our `eventSink` established by our `EventChannel`.

After we've told Stream that we're listening, we then need to bind to the channel's event stream. We add an event handler that implements [`ChatChannelEventHandler`](https://getstream.github.io/stream-chat-android/com/getstream/sdk/chat/rest/core/ChatChannelEventHandler.html). We override the one event we care about which is `onMessageNew`. Whenever we get a new event, we pull the message off and send it to the `eventSink`.

When the dart side has decided to cancel the stream, the `EventChannel`'s `onCancel` method will be called. We tell the channel we're done by calling `stopWatching`, remove the event handler and forget about the `EventChannel`.

### Step 2: Displaying messages

Now that we're streaming messages to our Flutter code and storing them in our `_messages` variable, we can show them. First, we build a `ListView` that contains our messages:

```dart
// mobile/lib/chat.dart:71
Widget buildMessages() {
  return Flexible(
    child: ListView(
      padding: EdgeInsets.all(10.0),
      reverse: true,
      children: _messages.reversed.map<Widget>(buildMessage).toList(),
    ),
  );
}
```

We reverse the list to show the most recent message on the bottom. This also makes it so the `ListView` scrolls to the bottom of the list by default, which is the messaging UX users expect. Each message is then it's own `Widget` that shows our messages on the right in a blue bubble and the other user's messages in a grey bubble on the left. 

```dart
// mobile/lib/chat.dart:51
Widget buildMessage(dynamic message) {
  return Row(
    mainAxisAlignment: message['userId'] == widget.account['user'] ? MainAxisAlignment.end : MainAxisAlignment.start,
    children: [
      Container(
        child: Text(
          message['text'],
          style: TextStyle(color: message['userId'] == widget.account['user'] ? Colors.white : Colors.black),
        ),
        padding: EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
        width: 200.0,
        decoration: BoxDecoration(
            color: message['userId'] == widget.account['user'] ? Colors.blueAccent : Colors.black12,
            borderRadius: BorderRadius.circular(8.0)),
        margin: EdgeInsets.only(bottom: 10.0, right: 10.0),
      )
    ],
  );
}
```

The final result will look like this:

![](images/chat-complete.png)

And that's it! You now have basic direct messaging between users.

## Final Thoughts

Now our app has the ability for a user to post updates to their activity stream and direct message other users. Using both the Activity Feed and Chat products from Stream allowed us to build this with virtually no backend. 

A big part of Flutter's power is the ability to leverage native iOS and Android libraries easily. You can do can get more for free by integrating Stream's out the box views. Utilizing Flutter's [AndroidView](https://api.flutter.dev/flutter/widgets/AndroidView-class.html) or [UiKitView](https://api.flutter.dev/flutter/widgets/UiKitView-class.html) we can embed Stream Chat Android's [https://github.com/GetStream/stream-chat-android/blob/master/docs/MessageList.md]. Keep in mind this level of integration is still considered in preview and is quite expensive, but it provides an even faster way to get up and running with Stream and Flutter.

Stream is also working hard building a pure [dart library](https://github.com/GetStream/stream-chat-dart). While it's not ready yet, be sure to check back and see when it's ready for production.
