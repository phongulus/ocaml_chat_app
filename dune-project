(lang dune 3.6)

(name ocaml_chat_app)

(generate_opam_files true)

(source
 (github phongulus/ocaml_chat_app))

(authors "Phong Le")

(maintainers "Phong Le")

(package
 (name ocaml_chat_app)
 (synopsis "OCaml Chat App")
 (description "Simple one-on-one chat app written in OCaml. Ahrefs test task.")
 (depends ocaml dune yojson core async ppx_yojson_conv ppx_jane))
