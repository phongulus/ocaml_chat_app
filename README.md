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


## App design

Communication between the server and client is encoded with a type `msg` that represent several types of messages: the actual chat messages sent by the user, acknowledgments of said chat messages, connection requests to the server, and acceptance of those requests sent to the client. For sending and receiving, this type converted to and from JSON format with `ppx_yojson_conv`.

The app is agnostic to the text encoding of the messages themselves - the messages are sent along as-is, and the onus is on the client and server to ensure they use the same text encoding.

## Limitations

- Only messages on one line can be sent. Pasting multiline messages into the command line will just result in multiple single-line messages being sent. If somehow a multiline message makes it into the JSON payload, the receiving side will be unable to decode the message (a warning will be shown to the recipient) and won't send any acknowledgment.
- 