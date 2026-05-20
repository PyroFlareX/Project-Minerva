fn main() {
    println!("cargo:rerun-if-changed=ui/");
    println!("cargo:rerun-if-changed=../torchform-shell/ui/tokens.slint");
    slint_build::compile("ui/apps.slint").expect("Slint compilation failed");
}
