use std::env;
use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::thread;
use std::time::Duration;

use xyrdp_probe::{is_tailscale_cgnat, parse_x224_confirm, probe_rdp_endpoint, RDP_X224_CONNECTION_REQUEST};

fn run_self_test() -> bool {
    let ok_ts = is_tailscale_cgnat(Ipv4Addr::new(100, 88, 10, 4))
        && !is_tailscale_cgnat(Ipv4Addr::new(10, 0, 0, 1));
    let sample_cc: [u8; 19] = [
        0x03, 0x00, 0x00, 0x13, 0x0e, 0xd0, 0x00, 0x01, 0x00, 0x01, 0x00, 0x02, 0x00, 0x08, 0x00,
        0x03, 0x00, 0x00, 0x00,
    ];
    let ok_pdu = RDP_X224_CONNECTION_REQUEST.len() == 19 && parse_x224_confirm(&sample_cc) == Some(3);
    ok_ts && ok_pdu
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let cpu_threads = thread::available_parallelism().map(|n| n.get()).unwrap_or(1);

    if args.iter().any(|a| a == "--self-test") {
        if run_self_test() {
            println!(
                "{{\"engine\":\"xyrdp-probe-rust\",\"self_test\":\"ok\",\"cpu_threads\":{}}}",
                cpu_threads
            );
            return ExitCode::SUCCESS;
        }
        eprintln!("{{\"engine\":\"xyrdp-probe-rust\",\"self_test\":\"failed\"}}");
        return ExitCode::from(2);
    }

    let mut target = String::from("127.0.0.1:3389");
    let mut timeout_ms: u64 = 1800;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--addr" if i + 1 < args.len() => {
                target = args[i + 1].clone();
                i += 1;
            }
            "--timeout-ms" if i + 1 < args.len() => {
                if let Ok(v) = args[i + 1].parse::<u64>() {
                    timeout_ms = v.clamp(100, 15_000);
                }
                i += 1;
            }
            _ => {}
        }
        i += 1;
    }

    let sock: SocketAddr = match target.parse() {
        Ok(s) => s,
        Err(err) => {
            eprintln!("{{\"error\":\"invalid_socket_addr\",\"detail\":\"{}\"}}", err);
            return ExitCode::from(2);
        }
    };

    let report = probe_rdp_endpoint(sock, Duration::from_millis(timeout_ms));
    println!("{}", report.to_json(cpu_threads));
    if report.x224_confirmed {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}
