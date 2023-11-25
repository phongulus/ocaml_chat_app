# OCaml Chat App

A basic, command-line based, one-on-one chat app written in OCaml using Jane Street's Async library.


## Build and usage instructions

This app was written and tested on OCaml 4.10.2. It is recommended you get this version if you don't have it with `opam switch create 4.10.2`. The app can then be built as follows:

```
opam update
opam install --deps-only .
dune build
```

To run the app in server mode, use the following. The `-port` flag is optional, the app will default to port 8765:

```
dune exec -- ocaml_chat_app server -name Louis -port 8765
```

To run the app in client mode, use the following. The `-addr` and `-port` flags, which should have the IP address and port of the server respectively, default to localhost (127.0.0.1) and 8765.

```
dune exec -- ocaml_chat_app client -name Igor -addr 127.0.0.1 -port 8765
```

You can set nicknames for the server and client using the `-name` flag above. Both the server and client will let you know once connection is established. Simply type your message and hit return to chat!

To exit the app, simply type `\quit` and hit return.


## App design

Communication between the server and client is encoded with a type `msg` that represent several types of messages: the actual chat messages sent by the user, acknowledgments of said chat messages, connection requests to the server, and acceptance of those requests sent to the client. For sending and receiving, this type converted to and from JSON format with `ppx_yojson_conv`.

A value of type `state` is initiated when the app starts to track the current state of the app. It contains the number of messages sent, the nicknames of the app instance and its partner, as well as the `Writer.t` used to dispatch messages to the remote server/client.

User input / message sending and message reception are handled by 2 deferreds. The first simply waits for user input - when that is available (the user typed newline), the message is read and dispatched to the remote chat partner if any. The second deferred waits for remote input by reading the `Reader.t` of Async's TCP server or connection, and reacts accordingly to the received communication (updating the `state` of the chat app and/or shooting back a message).

Only one client can communicate with the server at any given time. More clients can still connect to the server technically, but the server won't recognise them and won't send a connection acceptance. When the current client disconnects, another client will be accepted.

The app is agnostic to the text encoding of the messages themselves - the messages are sent along as-is, and the onus is on the client and server to ensure they use the same text encoding.

## Limitations

- Only messages on one line can be sent. Pasting multiline messages into the command line will just result in multiple single-line messages being sent. If somehow a multiline message makes it into the JSON payload, the receiving side will be unable to decode the message (a warning will be shown to the recipient) and won't send any acknowledgment.
- The communications between server and client are not encrypted in any way. The JSON payloads are sent verbatim.
- It's possible that the chat app receives and displays a "phantom" message acknowledgment. This is outside normal operation, and can happen if the app receives a rogue but correctly formatted acknowledgment JSON. This is because the app currently does not store any information about messages already sent.