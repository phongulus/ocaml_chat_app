(*
   Ahrefs Test Task: OCaml Chat App
   *)

open Core
open Async

type mode = Server | Client

(* type state = {
  my_name: string ref;
  partner_name: string ref;
  current_conn_writer: Writer.t option ref;
  msg_number: int ref;
} *)

(* Note: we don't assume anything about the message.
   Hence, no formatting is done on the messages, and they are sent as-is
   through the type below with Yojson. Including newline characters in
   the message string will lead to an invalid message. *)
type msg =
| Ack of int * string           (* Acknowledgment should contain the message number and the time sent (as a float string). *)
| Msg of int * string * string  (* Message number, the time sent for roundtrip duration calculation, and the actual message. *)
| Con of string                 (* Connection request should contain the nickname of the client. *)
| Acc of string                 (* Accept connection request from client, and send nickname of server. *)
| Err of string                 (* Not meant to be sent as an actual message, but returned when Yojson cannot decode something. *)
[@@deriving yojson]

(* TO-DO: try refactoring these as arguments of the functions instead of refs outside. *)
let my_name : string ref = ref "Anonymous"
let partner_name : string ref = ref "Anonymous"

(* Writer for the currently connected client. None when there is no connected client. *)
let current_conn_writer : Writer.t option ref = ref None

(* Message counter, to keep track of sent messages. *)
let msg_number : int ref = ref 1

(** Deferred responsible for input reading and sending messages.
    Dispatches message to client if connected. *)
let rec send_handler () =
  Reader.read_line (force Reader.stdin) >>= function
  | `Eof -> return ()
  | `Ok line ->
    if String.(line = "\\quit")
    then (Shutdown.shutdown 0; return ())
    else begin
      (match !current_conn_writer with
      | Some writer ->
          Writer.write_line
            writer
            (Msg (!msg_number,
                  Int63.to_string @@
                    Time_ns.to_int63_ns_since_epoch (Time_ns.now ()),
                  line) |> yojson_of_msg |> Yojson.Safe.to_string);
          Out_channel.print_endline @@
            !my_name ^ " #" ^ string_of_int !msg_number ^ " > " ^ line;
          incr msg_number
      | None -> Out_channel.print_endline
          "[No connection established. Ignoring message.]");
      send_handler ()
    end

(** Deferred responsible for receiving messages and responding to them
    (acknowledgments, accept connections...). *)
let rec recv_handler ~state ~reader ~writer =
  Reader.read_line reader >>= function
  (* The reader is closed, meaning that the remote client or server disconnected.
     Exit (client), or clean up and wait (server). *)
  | `Eof -> (match state with
    | Server ->
        Out_channel.print_endline
          "[Client disconnected, waiting for new connection.]";
        current_conn_writer := None;
        msg_number := 1;
        partner_name := "Anonymous";
        Reader.close reader >>= fun () -> Writer.close writer >>= return
    | Client ->
        Out_channel.print_endline "[Server disconnected, exiting now.]";
        return ());
  (* Read something from the remote server/client. Decode and respond. *)
  | `Ok line ->
    let msg = try msg_of_yojson (Yojson.Safe.from_string line) with
      | _ -> Err "[Invalid message received, I can't decode this.]" in
    (match msg with
    | Acc n -> 
        (match state with
        | Client -> Out_channel.print_endline @@
            "[Server \"" ^ n ^ "\" accepted connection! You can start chatting now.]";
            partner_name := n
        | Server -> Out_channel.print_endline
            "[Warning: server received accept connection message, which is supposed to be for clients only. Ignoring.]")
    | Ack (i, t) -> Out_channel.print_endline @@
        "[Message #" ^ string_of_int i ^ " acknowledged." ^
        " Roundtrip time: " ^
          string_of_float (Int63.(to_float @@
            (Time_ns.to_int63_ns_since_epoch (Time_ns.now ()) - of_string t)) /. 1000000.)
          ^ " ms]"
    | Msg (i, t, s) ->
        if i <> !msg_number
        then Out_channel.print_endline @@
          "[Warning: message #" ^ string_of_int i ^ " received out of order. Updating.]";
        let current_msg_number = max i !msg_number in
        Out_channel.print_endline @@
          !partner_name ^ " #" ^ string_of_int current_msg_number ^ " > " ^ s;
        msg_number := current_msg_number + 1;
        Ack (current_msg_number, t)
          |> yojson_of_msg
          |> Yojson.Safe.to_string
          |> Writer.write_line writer;
    | Con n ->
        Out_channel.print_endline @@
          "[Client \"" ^ n ^ "\" connected! You can start chatting now.]";
        partner_name := n;
        Acc !my_name
          |> yojson_of_msg
          |> Yojson.Safe.to_string
          |> Writer.write_line writer
    | Err e -> Out_channel.print_endline e);
    recv_handler ~state ~reader ~writer

let run_server ~port =
  Monitor.handle_errors (fun () ->
    Out_channel.print_endline @@
      "[Starting server \"" ^ !my_name ^ "\" on port " ^ string_of_int port ^ "...]";
    let server = Tcp.Server.create
      ~max_connections:1
      ~on_handler_error:`Raise
      (Tcp.Where_to_listen.of_port port)
      (fun _ r w ->
        current_conn_writer := Some w;
        recv_handler ~state:Server ~reader:r ~writer:w) in
    ignore (server : (Socket.Address.Inet.t, int) Tcp.Server.t Deferred.t);
    Deferred.never ())
    (fun e ->
      match Monitor.extract_exn e with
      | Unix.Unix_error (Unix.Error.EADDRINUSE, _, _) ->
          Out_channel.print_endline
            "[Someone's already here! Try another port? Exiting now.]";
          shutdown 0;
      | _ ->
          Out_channel.print_endline "Something went wrong... Here's the error:";
          Out_channel.print_endline @@ Exn.to_string e;
          Out_channel.print_endline "Exiting now."; shutdown 1)

let run_client ~host ~port =
  Monitor.handle_errors (fun () ->
    Tcp.with_connection
      ~timeout:(Time.Span.of_sec 5.)
      (Tcp.Where_to_connect.of_host_and_port { host; port })
      (fun _ r w ->
        Out_channel.print_endline "[Reached server! Waiting for server to accept connection request...]";
        current_conn_writer := Some w;
        Writer.write_line w (Con !my_name |> yojson_of_msg |> Yojson.Safe.to_string);
        recv_handler ~state:Client ~reader:r ~writer:w))
    (fun e ->
      match Monitor.extract_exn e with
      | Unix.Unix_error (Unix.Error.ECONNREFUSED, _, _) ->
          Out_channel.print_endline "[Server refused connection. Is it online? Exiting now.]"; shutdown 0;
      | _ ->
          Out_channel.print_endline "Something went wrong... Here's the error:";
          Out_channel.print_endline @@ Exn.to_string e;
          Out_channel.print_endline "Exiting now."; shutdown 1)

let () =
  Command.run @@ Command.async
    ~summary:"Ahrefs Test Task: Chat App" begin
      let%map_open.Command state =
        anon ("state" %: string)
        and name = flag "-name" (optional_with_default "Anonymous" string)
          ~doc:"Name of the client. Defaults to 'Anonymous'. Unused when running as a server."
        and host = flag "-addr" (optional_with_default "127.0.0.1" string)
          ~doc:"IP address for the client to connect to. Defaults to localhost (127.0.0.1). Unused when running as a server."
        and port = flag "-port" (optional_with_default 8765 int)
          ~doc:"Port for the client to connect to, and for the server to open at. Defaults to 8765." in
      fun () ->
        my_name := name;
        Deferred.any [send_handler ();
          match state with
          | "server" -> run_server ~port
          | "client" -> run_client ~host ~port
          | _ -> (Out_channel.print_endline "Invalid state input. Please use either 'server' or 'client'. Exiting now.";
            Shutdown.shutdown 1; return ())]
    end