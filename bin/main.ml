(*
   Ahrefs Test Task: OCaml Chat App
   *)

open Core
open Async
open Types
open Handlers
open Conn

let () =
  Command.run @@ Command.async
    ~summary:"Ahrefs Test Task: Chat App"
      (let%map_open.Command mode =
        anon ("mode" %: string)
        and name = flag "-name" (optional_with_default "" string)
          ~doc:"Name of the client. Defaults to either Server or Client depending on the app mode."
        and host = flag "-addr" (optional_with_default "127.0.0.1" string)
          ~doc:"IP address for the client to connect to. Defaults to localhost (127.0.0.1). Unused when running as a server."
        and port = flag "-port" (optional_with_default 8765 int)
          ~doc:"Port for the client to connect to, and for the server to open at. Defaults to 8765." in
      fun () ->
        let state = {
          my_name = ref name;
          partner_name = ref "";
          current_conn_writer = ref None;
          msg_number = ref 1;} in
        Deferred.any [send_handler ~state;
          match mode with
          | "server" -> run_server ~state ~port
          | "client" -> run_client ~state ~host ~port
          | _ ->
            (Out_channel.print_endline
              "Invalid state input. Please use either 'server' or 'client'. Exiting now.";
            Shutdown.shutdown 1; return ())])