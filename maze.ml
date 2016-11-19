
type action = Ast | Help | Error (*LLVM_IR | Compile*)

let help_string = (
    "Usage: ./maze [option] <source file>\n" ^
    "\n Valid Options: \n"^
    "\t -h: Help \n" ^
    "\t -c: Compile \n" ^ 
    "\t -l: Generate LLVM without checking \n" ^
    "\t -a: Print Abstract Syntax tree \n" 
)

let invalid_arg_string = ("Invalid Arguments")

let ast_holder = ("Ast would be printing")

let check_option = function
     "-h" -> Help, ""
    | _ as s -> Error, ""

let check_action = function  
      "-h" -> Help, ""
    | "-a" -> Ast, ""
    | _ as s -> Error, ""

let _ =  
    let action, filename  = 
        if Array.length Sys.argv = 1 then Help, "" 
        else if Array.length Sys.argv = 2 then check_option (Sys.argv.(1))
        else if Array.length Sys.argv = 3 then check_action (Sys.argv.(1)), Sys.argv.(2)
        else Error, ""
    (* 
    else Help in 
    let lexbuf = Lexing.from_channel stdin in 
    let ast = Parser.program Scanner.token lexbuf in 
    match action with 
        Ast -> print_string (Ast.string_of_program ast)
        | Help -> print_string help_string
*)

    in
    match action with 
        Help -> print_string help_string 
      | Ast -> print_string ast_holder
      | Error -> print_string invalid_arg_string




    
