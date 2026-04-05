// stream.rs — TCP → ffmpeg → raw RGBA frame pipeline.
//
// Connects to a local TCP port that is expected to stream raw H.264 data,
// decodes it via an ffmpeg subprocess, and delivers complete RGBA frames
// (width × height × 4 bytes) to a caller-supplied callback.
//
// The connection is retried indefinitely on any I/O error; panics are never
// used so the thread can outlive transient device disconnections.

use std::{
    io::{self, Read, Write},
    net::TcpStream,
    process::{Command, Stdio},
    sync::Arc,
    thread,
    time::Duration,
};

pub struct DisplayStream {
    port: u16,
    width: u32,
    height: u32,
}

impl DisplayStream {
    pub fn new(port: u16, width: u32, height: u32) -> Self {
        Self { port, width, height }
    }

    /// Spawn a background thread that connects to `127.0.0.1:{port}`, pipes the
    /// incoming data through ffmpeg, and calls `callback` with each complete
    /// RGBA frame wrapped in an `Arc<[u8]>`.
    pub fn start(
        self,
        callback: impl Fn(Arc<[u8]>) + Send + 'static,
    ) -> thread::JoinHandle<()> {
        let tag = format!("[stream-{}]", self.port);
        thread::spawn(move || {
            let frame_bytes = (self.width * self.height * 4) as usize;
            loop {
                if let Err(e) = run_once(self.port, frame_bytes, &callback) {
                    eprintln!("{tag} error: {e} — retrying in 1 s");
                }
                thread::sleep(Duration::from_secs(1));
            }
        })
    }
}

/// Single connection attempt.  Returns an error when the connection drops or
/// when ffmpeg exits unexpectedly; the caller loops and retries.
fn run_once(
    port: u16,
    frame_bytes: usize,
    callback: &impl Fn(Arc<[u8]>),
) -> io::Result<()> {
    // -------------------------------------------------------------------------
    // 1. Connect to the TCP source.
    // -------------------------------------------------------------------------
    let tcp = TcpStream::connect(("127.0.0.1", port))?;
    tcp.set_nodelay(true).ok();

    // -------------------------------------------------------------------------
    // 2. Spawn ffmpeg with stdin ← TCP, stdout → raw RGBA frames.
    // -------------------------------------------------------------------------
    let mut child = Command::new("ffmpeg")
        .args([
            "-loglevel", "error",
            "-f", "h264",
            "-i", "pipe:0",
            "-f", "rawvideo",
            "-pix_fmt", "rgba",
            "pipe:1",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| io::Error::new(e.kind(), format!("ffmpeg spawn failed: {e}")))?;

    let mut ffmpeg_stdin = child.stdin.take().expect("stdin piped");
    let mut ffmpeg_stdout = child.stdout.take().expect("stdout piped");

    // -------------------------------------------------------------------------
    // 3. Forward TCP bytes into ffmpeg stdin on a sibling thread so that
    //    reading stdout doesn't stall the pipe.
    // -------------------------------------------------------------------------
    let mut tcp_reader = tcp;
    let forward_thread = thread::spawn(move || {
        let mut buf = [0u8; 65536];
        loop {
            match tcp_reader.read(&mut buf) {
                Ok(0) => break, // connection closed
                Ok(n) => {
                    if ffmpeg_stdin.write_all(&buf[..n]).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        // Dropping ffmpeg_stdin signals EOF to ffmpeg.
        drop(ffmpeg_stdin);
    });

    // -------------------------------------------------------------------------
    // 4. Read complete frames from ffmpeg stdout and deliver to callback.
    // -------------------------------------------------------------------------
    let mut frame_buf = vec![0u8; frame_bytes];
    loop {
        match read_exact_or_eof(&mut ffmpeg_stdout, &mut frame_buf)? {
            ReadResult::Eof => break,
            ReadResult::Full => {
                let frame: Arc<[u8]> = Arc::from(frame_buf.as_slice());
                callback(frame);
            }
        }
    }

    forward_thread.join().ok();
    child.wait().ok();
    Ok(())
}

enum ReadResult {
    Full,
    Eof,
}

/// Read exactly `buf.len()` bytes.  Returns `Eof` if the stream closes before
/// the buffer is filled (i.e. mid-stream EOF counts as an error — we let the
/// caller retry).
fn read_exact_or_eof(r: &mut impl Read, buf: &mut [u8]) -> io::Result<ReadResult> {
    let mut filled = 0;
    while filled < buf.len() {
        match r.read(&mut buf[filled..]) {
            Ok(0) => return Ok(ReadResult::Eof),
            Ok(n) => filled += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(e),
        }
    }
    Ok(ReadResult::Full)
}
