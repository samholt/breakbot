let (>>=)      = Lwt.bind
let (=<<) f g  = Lwt.bind g f
let (>|=) f g  = Lwt.map g f
let (=|<) f g  = Lwt.map f g

module Lwt = struct
  include Lwt

  let of_opt = function
    | Some v -> return v
    | None   -> raise_lwt Not_found

  let bind_opt m =
    bind m (function Some v -> return v | None -> raise_lwt Not_found)
end

module Lwt_io = struct
  include Lwt_io
  open Lwt
  open Lwt_unix

  let tcp_conn_flags = [AI_FAMILY(PF_INET);
                        (* AI_FAMILY(PF_INET6);  *)
                        AI_SOCKTYPE(SOCK_STREAM)]

  let open_connection ?buffer_size ?sock_fun sockaddr =
    let fd = Lwt_unix.socket
      (Unix.domain_of_sockaddr sockaddr) Unix.SOCK_STREAM 0 in
    let close = lazy begin
      try_lwt
        Lwt_unix.shutdown fd Unix.SHUTDOWN_ALL;
        return ()
      with Unix.Unix_error(Unix.ENOTCONN, _, _) ->
      (* This may happen if the server closed the connection before us *)
        return ()
      finally
        Lwt_unix.close fd
    end in
    try_lwt
      lwt () = Lwt_unix.connect fd sockaddr in
      (try Lwt_unix.set_close_on_exec fd with Invalid_argument _ -> ());
      (try let sock_fun = Opt.unbox sock_fun in sock_fun fd with _ -> ());
      return (make ?buffer_size
                ~close:(fun _ -> Lazy.force close)
                ~mode:input (Lwt_bytes.read fd),
              make ?buffer_size
                ~close:(fun _ -> Lazy.force close)
                ~mode:output (Lwt_bytes.write fd))
    with exn ->
      lwt () = Lwt_unix.close fd in
      raise_lwt exn

  let with_connection_dns node service f =
    lwt addr_infos = getaddrinfo node service tcp_conn_flags in
    lwt addr_info =
      match addr_infos
      with h::t -> Lwt.return h | [] -> raise_lwt Not_found in
    Lwt_io.with_connection addr_info.ai_addr f

  let open_connection_dns ?sock_fun node service =
    lwt addr_infos = getaddrinfo node service tcp_conn_flags in
    lwt addr_info =
      match addr_infos
      with h::t -> Lwt.return h | [] -> raise_lwt Not_found in
    open_connection ?sock_fun addr_info.ai_addr
end

let print_to_stdout (ic, oc) : unit Lwt.t =
  let rec print_to_stdout () =
    lwt line = Lwt_io.read_line ic in
    lwt () = Lwt_io.printf "%s\n" line in
    print_to_stdout ()
  in print_to_stdout ()
