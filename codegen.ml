(* Codegen for MAZE - based off of MicroC *)

module L = Llvm
module A = Ast

module StringMap = Map.Make(String)


let translate (classes) =

    let grab_dbody someClass =
        someClass.A.dbody
    in

    let rec grab_fcn_lists = function
        [] -> []
      | [x] -> let y = x.A.methods in y
      | head :: tail -> let r = head.A.methods in r @ grab_fcn_lists tail
    in

    let dbodies = List.map grab_dbody classes in
    let functions = grab_fcn_lists dbodies in

    let context = L.global_context () in 
    let the_module = L.create_module context "maze"

    and i32_t = L.i32_type context      (* int *)
    and i8_t = L.i8_type context        (* printf *)
    and i1_t = L.i1_type context        (* bool *)
    and f_t = L.double_type context     (* float *)
    and void_t = L.void_type context    (* void *)
    and str_t = L.pointer_type (L.i8_type context) in
    (* add our other types here *)

    let typ_of_datatype = function
        A.Arraytype(p, i) -> p
      | A.Datatype(p) -> p
      | A.Any -> A.Null
    in

    let ltype_of_typ = function 
        A.Int -> i32_t 
      | A.Bool -> i1_t
      | A.Void -> void_t
      | A.String -> str_t
      | A.Float -> f_t
      | A.Char -> i8_t
      | A.Null -> i32_t in

    let ltype_of_formal = function
        A.Formal(t, n) -> ltype_of_typ(typ_of_datatype t)
    in

   let typeKey_of_formal = function
        A.Formal(t, n) -> (typ_of_datatype t, n)
    in

    let typeKey_of_local = function
        A.Field(t, n) -> (typ_of_datatype t, n)
    in

    let string_of_FName = function
        A.FName(f) -> f
      | A.Constructor -> ""
    in

    (* This is where global var func would go *)
    
    (* Lets make a function that does some of this boilerplate stuff
     * below so that we dont have to keep writing it out over and over
     * again for each function *)
    let printf_t = 
        L.var_arg_function_type i32_t [| L.pointer_type i8_t |] in
    let printf_func = 
        L.declare_function "printf" printf_t the_module in

    (* Define functions *)

    let function_decls = 
        let function_decl m fdecl =
            let name = (string_of_FName fdecl.A.fname)
            and formal_types = 
                Array.of_list (List.map ltype_of_formal fdecl.A.formals)
            in let ftype = 
                L.function_type (ltype_of_typ (typ_of_datatype fdecl.A.returnType)) formal_types in
            StringMap.add name (L.define_function name ftype the_module,
                                fdecl) m in
        List.fold_left function_decl StringMap.empty functions in

    (* Here we fill in the body of each of the functions *)

    let build_function_body fdecl = 

        let (the_function, _) = 
            StringMap.find (string_of_FName fdecl.A.fname) function_decls in

        let builder = 
            L.builder_at_end context (L.entry_block the_function) in

        (* print *)
        let int_format_str =
            L.build_global_stringptr "%d\n" "fmt" builder in
        let str_format_str =
            L.build_global_stringptr "%s\n" "fmt" builder in  
        let char_format_str =
	    L.build_global_stringptr "%c\n" "fmt" builder in
        let float_format_str = 
	    L.build_global_stringptr "%f\n" "fmt" builder in (* adds zeros to end of number *)

      
        (* For the cool TADS like feature I am going to 
         * need to do string formatting *)

    (* local variables - Print takes an argument,need this for hello world*)
    let local_vars = 
        let add_formal m (t, n) p = L.set_value_name n p;
          let local = L.build_alloca (ltype_of_typ t) n builder in 
          ignore (L.build_store p local builder);
          StringMap.add n local m in

        let add_local m (t, n) = 
            let local_var = L.build_alloca (ltype_of_typ t) n builder
            in StringMap.add n local_var m in

        let formals = List.fold_left2 add_formal StringMap.empty
            (List.map typeKey_of_formal fdecl.A.formals) (Array.to_list (L.params the_function)) in
        List.fold_left add_local formals (List.map typeKey_of_local fdecl.A.locals) in
    
    let lookup n = StringMap.find n local_vars in
    
    let type_of_val = function 
        "i32*" -> int_format_str (*int*)
      | "i8**" -> str_format_str (*string*)
      | "i8*" -> char_format_str (*char*)
      | "i1*" -> int_format_str (*bool*)
      | "double*" -> float_format_str (*float*)
      | _ -> str_format_str
    in 

    let check_print_input = function
        A.Int_Lit e -> int_format_str
      | A.String_Lit e -> str_format_str 
      | A.Char_Lit c -> char_format_str 
      | A.Float_Lit f -> float_format_str 
      | A.Binop (e1, op, e2) -> int_format_str 
      | A.Bool_Lit b -> int_format_str 
      | A.Id s -> type_of_val(L.string_of_lltype(L.type_of (lookup s)))
      | A.Assign (s, e) -> int_format_str
      | A.Noexpr -> int_format_str
      | A.Unop (op, e) -> int_format_str
      | A.Call (s, actuals) -> int_format_str
      | A.Null -> int_format_str
    in 
    
    (* Generate code for an expression *)

    let rec expr builder = function 
        A.Int_Lit i -> L.const_int i32_t i
      | A.Bool_Lit b -> L.const_int i1_t (if b then 1 else 0)
      | A.String_Lit s -> L.build_global_stringptr s "str" builder
      | A.Noexpr -> L.const_int i32_t 0
      | A.Id s -> L.build_load (lookup s) s builder
      | A.Binop (e1, op, e2) ->
	  let e1' = expr builder e1
	  and e2' = expr builder e2 
	  and float_ops = (match op with
	    A.Add     -> L.build_fadd
	  | A.Sub     -> L.build_fsub
	  | A.Mult    -> L.build_fmul
          | A.Div     -> L.build_fdiv
	  | A.And     -> L.build_and
	  | A.Or      -> L.build_or
	  | A.Equal   -> L.build_fcmp L.Fcmp.Oeq
	  | A.Neq     -> L.build_fcmp L.Fcmp.One
	  | A.Less    -> L.build_fcmp L.Fcmp.Olt
	  | A.Leq     -> L.build_fcmp L.Fcmp.Ole
	  | A.Greater -> L.build_fcmp L.Fcmp.Ogt
	  | A.Geq     -> L.build_fcmp L.Fcmp.Oge
	  )
 
          and int_ops = match op with
	    A.Add     -> L.build_add
	  | A.Sub     -> L.build_sub
	  | A.Mult    -> L.build_mul
          | A.Div     -> L.build_sdiv
	  | A.And     -> L.build_and
	  | A.Or      -> L.build_or
	  | A.Equal   -> L.build_icmp L.Icmp.Eq
	  | A.Neq     -> L.build_icmp L.Icmp.Ne
	  | A.Less    -> L.build_icmp L.Icmp.Slt
	  | A.Leq     -> L.build_icmp L.Icmp.Sle
	  | A.Greater -> L.build_icmp L.Icmp.Sgt
	  | A.Geq     -> L.build_icmp L.Icmp.Sge in
          if(L.type_of e1' = f_t || L.type_of e2' = f_t) then float_ops e1' e2' "tmp" builder
	  else int_ops e1' e2' "tmp" builder

   (* | A.ObjCreate(id, e1) ->
	  let f = func_lookup id in
	  let params = List.map (expr builder) e1 in
	  let obj = L.build_call f (Array.of_list params) "tmp" builder in
	  obj *)


      | A.Unop(op, e) ->
	  let e' = expr builder e in
	  (match op with
	    A.Neg     -> L.build_neg
          | A.Not     -> L.build_not) e' "tmp" builder
      | A.Assign (s, e) -> let e' = expr builder e in
                ignore (L.build_store e' (lookup s) builder); e'
      | A.Float_Lit f -> L.const_float f_t f
      | A.Char_Lit c -> L.const_int i8_t (Char.code c)
      | A.Null -> L.const_null i32_t
      | A.Call ("print", [e]) -> L.build_call printf_func
                 [| check_print_input e; (expr builder e) |]
                 "printf" builder
      (* This evaluates arguments backwards *)
      | A.Call (f, act) ->
         let (fdef, fdecl) = StringMap.find f function_decls in
         let actuals =
             List.rev (List.map (expr builder) (List.rev act)) in
         let result = (match (typ_of_datatype fdecl.A.returnType) with A.Void -> ""
                                            | _ -> f ^ "_result") in
         L.build_call fdef (Array.of_list actuals) result builder in
      
      (* MicroC has a helper here: add_terminal *)
      let add_terminal builder f =
          match L.block_terminator (L.insertion_block builder) with
          Some _ -> ()
        | None -> ignore (f builder) in


      (* define statements here *)
      let rec stmt builder = function 
          A.Block sl -> List.fold_left stmt builder sl

        | A.Expr e -> ignore (expr builder e); builder

        | A.Return e -> ignore (match (typ_of_datatype fdecl.A.returnType) with
          A.Void -> L.build_ret_void builder
        | _ -> L.build_ret (expr builder e) builder); builder
         
        | A.If (pred, then_stmt, else_stmt) ->
	    let bool_val = expr builder pred in
	    let merge_bb = L.append_block context "merge" the_function in
	    let then_bb = L.append_block context "then" the_function in
	    add_terminal (stmt (L.builder_at_end context then_bb) then_stmt) (L.build_br merge_bb);
	    let else_bb = L.append_block context "else" the_function in
	    add_terminal (stmt (L.builder_at_end context else_bb) else_stmt) (L.build_br merge_bb);

	    ignore (L.build_cond_br bool_val then_bb else_bb builder);
	    L.builder_at_end context merge_bb 

        | A.While (pred, body) ->
	   let pred_bb = L.append_block context "while" the_function in
	   ignore (L.build_br pred_bb builder);
	   let body_bb = L.append_block context "while_body" the_function in
	   add_terminal (stmt (L.builder_at_end context body_bb) body) (L.build_br pred_bb);
	   let pred_builder = L.builder_at_end context pred_bb in
	   let bool_val = expr pred_builder pred in
	   let merge_bb = L.append_block context "merge" the_function in
	   ignore (L.build_cond_br bool_val body_bb merge_bb pred_builder);
	   L.builder_at_end context merge_bb

in

      (* Code for each statement in the function *)
      let builder = stmt builder (A.Block fdecl.A.body) in

      (*MicroC behavior here is to have program return void 
       * if control falls off the end of the program *)
      add_terminal builder (match (typ_of_datatype fdecl.A.returnType) with
          A.Void -> L.build_ret_void 
        | t -> L.build_ret (L.const_int (ltype_of_typ t) 0))
      in


      List.iter build_function_body functions;
      the_module
