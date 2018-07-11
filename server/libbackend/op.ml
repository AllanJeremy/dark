open Core_kernel
open Libexecution
open Types


(* DO NOT CHANGE THE ORDER ON THESE!!!! IT WILL BREAK THE SERIALIZER *)
type op = SetHandler of tlid * pos * Handler.handler
        | CreateDB of tlid * pos * string
        | AddDBCol of tlid * id * id
        | SetDBColName of tlid * id * string
        | SetDBColType of tlid * id * string
        | DeleteTL of tlid
        | MoveTL of tlid * pos
        | DeprecatedSavepoint
        | DeprecatedDeleteAll
        | DeprecatedUndo
        | DeprecatedRedo
        | SetFunction of RuntimeT.user_fn
        | ChangeDBColName of tlid * id * string
        | ChangeDBColType of tlid * id * string
        | UndoTL of tlid
        | RedoTL of tlid
        | DeprecatedSavepoint2 of tlid list
        | InitDBMigration of tlid * id * id * id * RuntimeT.DbT.migration_kind
        | SetExpr of tlid * id * RuntimeT.expr
        | TLSavepoint of tlid
        [@@deriving eq, yojson, show, sexp, bin_io]
(* DO NOT CHANGE THE ORDER ON THESE!!!! IT WILL BREAK THE SERIALIZER *)

type oplist = op list [@@deriving eq, yojson, show, sexp, bin_io]

let has_effect (op: op) : bool  =
  match op with
  | TLSavepoint _ -> false
  | DeprecatedSavepoint -> false
  | DeprecatedSavepoint2 _ -> false
  | _ -> true

let tlidsOf (op: op) :  tlid list =
  match op with
  | SetHandler (tlid, _, _) -> [tlid]
  | CreateDB (tlid, _, _) -> [tlid]
  | AddDBCol (tlid, _, _) -> [tlid]
  | SetDBColName (tlid, _, _) -> [tlid]
  | ChangeDBColName (tlid, _, _) -> [tlid]
  | SetDBColType (tlid, _, _) -> [tlid]
  | ChangeDBColType (tlid, _, _) -> [tlid]
  | InitDBMigration (tlid, _, _, _, _) -> [tlid]
  | SetExpr (tlid, _, _) -> [tlid]
  | DeprecatedSavepoint2 tlids -> tlids
  | TLSavepoint tlid -> [tlid]
  | UndoTL tlid -> [tlid]
  | RedoTL tlid -> [tlid]
  | DeleteTL tlid -> [tlid]
  | MoveTL (tlid, _) -> [tlid]
  | SetFunction f -> [f.tlid]
  | DeprecatedSavepoint -> []
  | DeprecatedUndo -> []
  | DeprecatedRedo -> []
  | DeprecatedDeleteAll -> []


