fn main() {
    println!("cargo:rerun-if-changed=emulator.slint");

    let config = slint_build::CompilerConfiguration::new()
        .with_style("fluent-dark".into());

    slint_build::compile_with_config("emulator.slint", config)
        .expect("Slint compilation failed");
}
