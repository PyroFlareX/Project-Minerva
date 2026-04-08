// build.rs — Compile all .slint files in ui/ into Rust bindings.

fn main() {
    println!("cargo:rerun-if-changed=ui/");

    let config = slint_build::CompilerConfiguration::new()
        .with_style("fluent-dark".into());

    slint_build::compile_with_config("ui/main.slint", config)
        .expect("Slint compilation failed");
}
