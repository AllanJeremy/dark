open Core
open Lwt

module Clu = Cohttp_lwt_unix
module S = Clu.Server
module CRequest = Clu.Request
module Header = Cohttp.Header
module C = Canvas
module RT = Runtime
module RTT = Types.RuntimeT
module TL = Toplevel
module DReq = Dark_request

let server =
  let stop,stopper = Lwt.wait () in

  let callback _ req req_body =

    let admin_rpc_handler body (host: string) (save: bool) : string =
      let time = Unix.gettimeofday () in
      let body = Log.pp "request body" body ~f:ident in
      let c = C.load host [] in
      try
        let ops = Api.to_ops body in
        c := !(C.load host ops);
        let global = DReq.sample |> DReq.to_dval in
        let dbs_env = Db.dbs_as_env (TL.dbs !c.toplevels) in
        let env = RTT.DvalMap.add dbs_env "request" global in
        let result = C.to_frontend_string env !c in
        let total = string_of_float (1000.0 *. (Unix.gettimeofday () -. time)) in
        Log.pP ~stop:10000 ~f:ident ("response (" ^ total ^ "ms):") result;
        (* work out the result before we save it, incase it has a stackoverflow
         * or other crashing bug *)
        if save then C.save !c;
        result
      with
      | e ->
        let bt = Exn.backtrace () in
        let msg = Exn.to_string e in
        print_endline (C.show_canvas !c);
        print_endline ("Exception: " ^ msg);
        print_endline bt;
        raise e
    in

    let admin_ui_handler () =
      let template = Util.readfile_lwt "templates/ui.html" in
      template >|= Util.string_replace "ALLFUNCTIONS" (Api.functions)
    in

    let static_handler uri =
      let fname = S.resolve_file ~docroot:"." ~uri in
      S.respond_file ~fname ()
    in

    let save_test_handler host =
      let g = C.load host [] in
      let filename = C.save_test !g in
      S.respond_string ~status:`OK ~body:("Saved as: " ^ filename) ()
    in

    let user_page_handler (host: string) (uri: Uri.t) (req: CRequest.t) (body: string) =
      let c = C.load host [] in
      let pages = C.pages_matching_route ~uri:uri !c in
      match pages with
      | [] ->
        S.respond_string ~status:`Not_found ~body:"404: No page matches" ()
      | [page] ->
        let route = Handler.url_for_exn page in
        let input = DReq.from_request req body uri in
        let bound = Http.bind_route_params_exn ~uri ~route in
        let dbs_env = Db.dbs_as_exe_env (TL.dbs !c.toplevels) in
        let env = Util.merge_left bound dbs_env in
        let env = Map.add ~key:"request" ~data:(DReq.to_dval input) env in
        let result = Handler.execute env page in
        (match result with
        | DResp (http, value) ->
          let url_safe = RT.to_url_string value in
          (match http with
           | Redirect url ->
             S.respond_redirect (Uri.of_string url) ()
           | Response code ->
             S.respond_string
               ~status:(Cohttp.Code.status_of_code code)
               ~body:url_safe
               ())
        | _ ->
          let url_safe = RT.to_url_string result in
          S.respond_string
            ~status:`Bad_request
            ~body:("400: Handler did not return a HTTP response, instead returned: " ^ url_safe)
            ())
      | _ ->
        S.respond_string ~status:`Internal_server_error ~body:"500: More than one page matches" ()
    in

    (* let auth_handler handler *)
    (*   = match auth with *)
    (*   | (Some `Basic ("dark", "eapnsdc")) *)
    (*     -> handler *)
    (*   | _ *)
    (*     -> Cohttp_lwt_unix.Server.respond_need_auth ~auth:(`Basic "dark") () *)
    (* in *)
    (*  *)
    let route_handler _ =
      req_body |> Cohttp_lwt__Body.to_string >>=
      (fun req_body ->
         try
           let uri = req |> CRequest.uri in
           let verb = req |> CRequest.meth in
           (* let auth = req |> Request.headers |> Header.get_authorization in *)

           let domain = Uri.host uri |> Option.value ~default:"" in
           let domain = match String.split domain '.' with
           | ["localhost"] -> "localhost"
           | a :: rest -> a
           | _ -> failwith @@ "Unsupported domain: " ^ domain in

           Log.pP "req: " (domain, Cohttp.Code.string_of_method verb, uri);

           match (Uri.path uri) with
           | "/admin/api/rpc" ->
             S.respond_string ~status:`OK
                              ~body:(admin_rpc_handler req_body domain true) ()
           | "/admin/api/phantom" ->
             S.respond_string ~status:`OK
                              ~body:(admin_rpc_handler req_body domain false) ()
           | "/sitemap.xml" ->
             S.respond_string ~status:`OK ~body:"" ()
           | "/favicon.ico" ->
             S.respond_string ~status:`OK ~body:"" ()
           | "/admin/api/shutdown" ->
             Lwt.wakeup stopper ();
             S.respond_string ~status:`OK ~body:"Disembowelment" ()
           | "/admin/ui" ->
             admin_ui_handler () >>= fun body -> S.respond_string ~status:`OK ~body ()
           | "/admin/test" ->
             static_handler (Uri.of_string "/templates/test.html")
           | "/admin/api/save_test" ->
             save_test_handler domain
           | p when (String.length p) < 8 ->
             user_page_handler domain uri req req_body
           | p when (String.equal (String.sub p ~pos:0 ~len:8) "/static/") ->
             static_handler uri
           | _ ->
             user_page_handler domain uri req req_body
         with
         | e ->
           let backtrace = Exn.backtrace () in
           let body = match e with
             | Exception.DarkException e ->
                 Exception.exception_data_to_yojson e |> Yojson.Safe.pretty_to_string
             | Yojson.Json_error msg -> "Not a value: " ^ msg
             | Postgresql.Error e -> "Postgres error: " ^ Postgresql.string_of_error e
             | _ -> "Dark Internal Error: " ^ Exn.to_string e
           in
           Lwt_io.printl ("Error: " ^ body) >>= fun () ->
           Lwt_io.printl backtrace >>= fun () ->
           S.respond_string ~status:`Internal_server_error ~body ())
    in
    ()
    |> route_handler
    (* |> auth_handler *)
  in
  S.create ~stop ~mode:(`TCP (`Port 8000)) (S.make ~callback ())

let run () = ignore (Lwt_main.run server)
