// We need to forward routine registration from C to Rust
// to avoid the linker removing the static library.
//
// The init hook is named after the R package (`terrio`); the registration
// routine comes from the Rust module `terrioR` (see src/rust/src/lib.rs).

void R_init_terrioR_extendr(void *dll);
void register_extendr_panic_hook(void);

void R_init_terrio(void *dll) {
    register_extendr_panic_hook();
    R_init_terrioR_extendr(dll);
}
