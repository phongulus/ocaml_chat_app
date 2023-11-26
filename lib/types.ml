open Core
open Async

(*
   Simple variant to let the message receipt handler know whether
   the current chat instance is a server or client. *)
type mode = Server | Client

(*
   Type to keep track of the current state of the chat app, namely:
    - The name of the remote chat partner.
    - The current writer for sending data remotely.
    - The current message number.
   A single state is to be initialized in the beginning and passed
   to both the user input handler and the TCP connection instance with
   the message receipt handler. This will allow the two to communicate. *)
type state = {
  my_name: string ref;
  partner_name: string ref;
  current_conn_writer: Writer.t option ref;
  msg_number: int ref;
}

(* Note: we don't assume anything about the message.
   Hence, no formatting is done on the messages, and they are sent as-is
   through the type below with Yojson. Including newline characters in
   the message string will lead to an invalid message. *)
type msg =
| Ack of int * string           (* Acknowledgment should contain the message number and the time the original message was sent. *)
| Msg of int * string * string  (* Message number, the time sent for roundtrip duration calculation, and the actual message. *)
| Con of string                 (* Connection request should contain the nickname of the client. *)
| Acc of string                 (* Accept connection request from client, and send nickname of server. *)
| Err of string                 (* Not meant to be sent as an actual message, but returned when Yojson cannot decode something. *)
[@@deriving yojson]