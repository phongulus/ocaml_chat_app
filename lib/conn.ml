open Core
open Async
open Types
open Handlers

let run_server ~state ~port =
  Monitor.handle_errors
    (fun () ->
      Out_channel.print_endline @@
        "[Starting server \"" ^ state.my_name ^ "\" on port " ^ string_of_int port ^ "...]";
      let server = Tcp.Server.create
        ~max_connections:1
        ~on_handler_error:`Raise
        (Tcp.Where_to_listen.of_port port)
        (fun _ r w ->
          state.current_conn_writer := Some w;
          recv_handler ~state ~mode:Server ~reader:r ~writer:w) in
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

let run_client ~state ~host ~port =
  Monitor.handle_errors
    (fun () ->
      Tcp.with_connection
        ~timeout:(Time.Span.of_sec 5.)
        (Tcp.Where_to_connect.of_host_and_port { host; port })
        (fun _ r w ->
          Out_channel.print_endline "[Reached server! Waiting for server to accept connection request...]";
          Writer.write_line w (Con state.my_name |> yojson_of_msg |> Yojson.Safe.to_string);
          recv_handler ~state ~mode:Client ~reader:r ~writer:w))
    (fun e ->
      match Monitor.extract_exn e with
      | Unix.Unix_error (Unix.Error.ECONNREFUSED, _, _) ->
          Out_channel.print_endline "[Server refused connection. Is it online? Exiting now.]"; shutdown 0;
      | _ ->
          Out_channel.print_endline "Something went wrong... Here's the error:";
          Out_channel.print_endline @@ Exn.to_string e;
          Out_channel.print_endline "Exiting now."; shutdown 1)