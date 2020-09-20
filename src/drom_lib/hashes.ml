(**************************************************************************)
(*                                                                        *)
(*    Copyright 2020 OCamlPro & Origin Labs                               *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

open EzCompat

(* Management of .drom file of hashes *)

type t = {
  mutable hashes : string StringMap.t ;
  mutable modified : bool ;

  (* for git *)
  mutable to_add : StringSet.t ;
  mutable to_remove : StringSet.t ;
}

let load () =
  let hashes =
    if Sys.file_exists ".drom" then (
      let map = ref StringMap.empty in
      (* Printf.eprintf "Loading .drom\n%!"; *)
      Array.iter
        (fun line ->
           if line <> "" && line.[0] <> '#' then
             let digest, filename = EzString.cut_at line ' ' in
             let digest = Digest.from_hex digest in
             map := StringMap.add filename digest !map)
        (EzFile.read_lines ".drom");
      !map )
    else StringMap.empty
  in
  { hashes ;
    modified = false ;
    to_add = StringSet.empty ;
    to_remove = StringSet.empty ;
  }

let save ?(git=true) t =
  if t.modified then begin
    let b = Buffer.create 1000 in
    Printf.bprintf b
      "# Keep this file in your GIT repo to help drom track generated files\n";
    StringMap.iter
      (fun filename hash ->
         if Sys.file_exists filename then
           Printf.bprintf b "%s %s\n" (Digest.to_hex hash) filename)
      t.hashes;
    EzFile.write_file ".drom" (Buffer.contents b);

    if git && Sys.file_exists ".git" then (
      let to_remove = ref [] in
      StringSet.iter (fun file ->
          if not ( Sys.file_exists file) then
            to_remove := file :: !to_remove
        ) t.to_remove;
      if !to_remove <> [] then
        Git.run ( "rm" :: "-f" :: !to_remove );

      let to_add = ref [] in
      StringSet.iter (fun file ->
          if Sys.file_exists file then
            to_add := file :: !to_add
        ) t.to_add;
      Git.run ( "add" :: ".drom" :: !to_add );

    );
    t.to_add <- StringSet.empty;
    t.to_remove <- StringSet.empty;
    t.modified <- false
  end

let get t file =
  StringMap.find file t.hashes

let update t file hash =
  t.hashes <- StringMap.add file hash t.hashes;
  t.to_add <- StringSet.add file t.to_add;
  t.modified <- true

let remove t file =
  t.hashes <- StringMap.remove file t.hashes;
  t.to_remove <- StringSet.add file t.to_remove;
  t.modified <- true

let rename t src_file dst_file =
  match get t src_file with
  | exception Not_found -> ()
  | digest ->
      remove t src_file ;
      update t dst_file digest

let digest_file file = Digest.file file
let digest_string file = Digest.string file

let with_ctxt ?git f =
  let t = load () in
  match f t with
  | res ->
      save ?git t;
      res
  | exception exn ->
      let bt = Printexc.get_raw_backtrace () in
      Printf.eprintf "An error happened. Saving intermediate changes.\n%!";
      save t;
      Printexc.raise_with_backtrace exn bt
