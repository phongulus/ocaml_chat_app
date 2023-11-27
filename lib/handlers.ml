open Core
open Async
open Types

(** Attempt to write to the provided writer. We note that we don't
    need to handle anything in particular if the writer is closed.
    Async should have already closed the associated reader, signalling
    a disconnect, by the next recv_handler deferred. *)
let send_maybe w msg =
  match msg with
  | Err e -> Out_channel.print_endline e (* Don't send errors. *)
  | _ ->
    if Writer.is_open w
    then yojson_of_msg msg |> Yojson.Safe.to_string |> Writer.write_line w
    else Out_channel.print_endline
      "[Warning: the writer is closed. The remote server/client may have disconnected.]"

(** Update message number in reference when receiving a Msg or Ack. Reset to 0 if needed. *)
let update_msg_number msg_number_ref i =
  if i - !msg_number_ref = 1 || i - !msg_number_ref = 0 then
    msg_number_ref := i
  else
    (Out_channel.print_endline @@ "[Warning: message number out of order. Updating.]";
    msg_number_ref := max i !msg_number_ref)

(** Deferred responsible for input reading and sending messages.
    Dispatches message to client if connected. *)
let rec send_handler ~state =
  Reader.read_line (force Reader.stdin) >>= function
  | `Eof -> return ()
  | `Ok line ->
    if String.(line = "\\quit")
    then (Shutdown.shutdown 0; return ())
    else begin
      (match !(state.current_conn_writer) with
      | Some writer ->
          incr state.msg_number;
          Msg (!(state.msg_number),
              Int63.to_string Time_ns.(to_int63_ns_since_epoch (now ())),
              line) |> send_maybe writer;
          Out_channel.print_endline @@
            !(state.my_name) ^ " #" ^ string_of_int !(state.msg_number) ^ " > " ^ line;
      | None -> Out_channel.print_endline
          "[No connection established. Ignoring message.]");
      send_handler ~state
    end

(** Deferred responsible for receiving messages and responding to them
    (acknowledgments, accept connections...). *)
let rec recv_handler ~state ~mode ~reader ~writer =
  Reader.read_line reader >>= function
  (* The reader is closed, meaning that the remote client or server disconnected.
      Exit (client), or clean up and wait (server). *)
  | `Eof -> (match mode with
    | Server ->
        Out_channel.print_endline
          "[Client disconnected, waiting for new connection.]";
        state.current_conn_writer := None;
        state.msg_number := 0;
        state.partner_name := "Client";
    | Client ->
        Out_channel.print_endline "[Server disconnected, exiting now.]");
    let%bind _ = Reader.close reader in Writer.close writer

  (* Read something from the remote server/client. Decode and respond. *)
  | `Ok line ->
    let msg = try Yojson.Safe.from_string line |> msg_of_yojson with
      | _ -> Err "[Invalid message received, I can't decode this.]" in
    (match msg with
    | Acc n ->
        (match mode with
        | Client -> Out_channel.print_endline @@
            "[Server \"" ^ n ^ "\" accepted connection! You can start chatting now.]";
            state.partner_name := n;
            state.current_conn_writer := Some writer
        | Server -> Out_channel.print_endline
            "[Warning: server received accept connection message, which is supposed to be for clients only. Ignoring.]")
    | Ack (i, t) ->
        update_msg_number state.msg_number i;
        (try
          let roundtrip = string_of_float @@
            Int63.(Time_ns.(to_int63_ns_since_epoch (now ())) - of_string t |> to_float) /. 1000000. in
          Out_channel.print_endline @@
            "[Message #" ^ string_of_int i ^ " acknowledged. Roundtrip time: " ^ roundtrip ^ " ms]"
        with _ -> Out_channel.print_endline @@
          "[Warning: message #" ^ string_of_int i ^ " acknowledgment received but invalid roundtrip time.]")
    | Msg (i, t, s) ->
        update_msg_number state.msg_number i;
        Out_channel.print_endline @@
          !(state.partner_name) ^ " #" ^ string_of_int !(state.msg_number) ^ " > " ^ s;
        Ack (!(state.msg_number), t) |> send_maybe writer;
    | Con n ->
        Out_channel.print_endline @@
          "[Client \"" ^ n ^ "\" connected! You can start chatting now.]";
        state.partner_name := n;
        Acc !(state.my_name) |> send_maybe writer;
    | Err e -> Out_channel.print_endline e);
    recv_handler ~state ~mode ~reader ~writer
