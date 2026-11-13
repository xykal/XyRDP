//! Modul inti telemetri & verifikasi handshake RDP X.224 untuk XyRDP.
//! Dikembangkan oleh xykal (Haekal Saputra) · Tim XyVerse · Indonesia.

use std::io::{Read, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream};
use std::time::{Duration, Instant};

/// Paket X.224 Connection Request standar RDP di atas TPKT v3 (19 byte),
/// meminta negosiasi TLS + CredSSP/Hybrid (requestedProtocols = 0x00000003).
pub const RDP_X224_CONNECTION_REQUEST: [u8; 19] = [
    0x03, 0x00, 0x00, 0x13, // TPKT Header: version=3, reserved=0, length=19
    0x0e,                   // X.224 Length Indicator (14 byte sesudah byte ini)
    0xe0,                   // X.224 Connection Request (CR = 0xE0)
    0x00, 0x00,             // dst-ref
    0x00, 0x01,             // src-ref
    0x00,                   // class 0
    0x01,                   // TYPE_RDP_NEG_REQ
    0x00,                   // flags
    0x08, 0x00,             // length = 8
    0x03, 0x00, 0x00, 0x00, // PROTOCOL_SSL (1) | PROTOCOL_HYBRID (2)
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RdpProbeReport {
    pub target: String,
    pub reachable: bool,
    pub x224_confirmed: bool,
    pub selected_protocol: u32,
    pub rtt_ms: u64,
    pub tailscale_cgnat: bool,
    pub note: String,
}

/// Cek apakah alamat IPv4 berada di ruang CGNAT Tailscale (`100.64.0.0/10`,
/// yaitu `100.64.0.0` s/d `100.127.255.255`).
pub fn is_tailscale_cgnat(ip: Ipv4Addr) -> bool {
    let oct = ip.octets();
    oct[0] == 100 && (oct[1] & 0b1100_0000) == 64
}

/// Validasi balasan TPKT + X.224 Connection Confirm (`0xD0`) dari server RDP.
pub fn parse_x224_confirm(buf: &[u8]) -> Option<u32> {
    if buf.len() < 11 {
        return None;
    }
    // TPKT version wajib 3, dan kode TPDU X.224 Connection Confirm = 0xD0 (4 bit atas = 0xD)
    if buf[0] != 0x03 || (buf[5] & 0xF0) != 0xD0 {
        return None;
    }
    let tpkt_len = u16::from_be_bytes([buf[2], buf[3]]) as usize;
    if tpkt_len < 11 {
        return None;
    }
    // Jika server menyertakan RDP_NEG_RSP (type = 0x02, panjang 8 byte)
    if buf.len() >= 19 && buf[11] == 0x02 {
        let proto = u32::from_le_bytes([buf[15], buf[16], buf[17], buf[18]]);
        return Some(proto);
    }
    Some(0)
}

/// Lakukan uji koneksi nyata + handshake X.224 ke endpoint RDP (`host:port`).
pub fn probe_rdp_endpoint(addr: SocketAddr, timeout: Duration) -> RdpProbeReport {
    let is_ts = match addr.ip() {
        IpAddr::V4(v4) => is_tailscale_cgnat(v4),
        IpAddr::V6(_) => false,
    };
    let start = Instant::now();
    let mut stream = match TcpStream::connect_timeout(&addr, timeout) {
        Ok(s) => s,
        Err(err) => {
            return RdpProbeReport {
                target: addr.to_string(),
                reachable: false,
                x224_confirmed: false,
                selected_protocol: 0,
                rtt_ms: start.elapsed().as_millis() as u64,
                tailscale_cgnat: is_ts,
                note: format!("tcp_connect_failed: {}", err),
            };
        }
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    if let Err(err) = stream.write_all(&RDP_X224_CONNECTION_REQUEST) {
        return RdpProbeReport {
            target: addr.to_string(),
            reachable: true,
            x224_confirmed: false,
            selected_protocol: 0,
            rtt_ms: start.elapsed().as_millis() as u64,
            tailscale_cgnat: is_ts,
            note: format!("x224_write_failed: {}", err),
        };
    }

    let mut resp = [0u8; 64];
    match stream.read(&mut resp) {
        Ok(n) if n >= 11 => {
            let rtt = start.elapsed().as_millis() as u64;
            if let Some(proto) = parse_x224_confirm(&resp[..n]) {
                RdpProbeReport {
                    target: addr.to_string(),
                    reachable: true,
                    x224_confirmed: true,
                    selected_protocol: proto,
                    rtt_ms: rtt,
                    tailscale_cgnat: is_ts,
                    note: "rdp_x224_ready".to_string(),
                }
            } else {
                RdpProbeReport {
                    target: addr.to_string(),
                    reachable: true,
                    x224_confirmed: false,
                    selected_protocol: 0,
                    rtt_ms: rtt,
                    tailscale_cgnat: is_ts,
                    note: "unexpected_tpkt_payload".to_string(),
                }
            }
        }
        Ok(_) => RdpProbeReport {
            target: addr.to_string(),
            reachable: true,
            x224_confirmed: false,
            selected_protocol: 0,
            rtt_ms: start.elapsed().as_millis() as u64,
            tailscale_cgnat: is_ts,
            note: "short_x224_response".to_string(),
        },
        Err(err) => RdpProbeReport {
            target: addr.to_string(),
            reachable: true,
            x224_confirmed: false,
            selected_protocol: 0,
            rtt_ms: start.elapsed().as_millis() as u64,
            tailscale_cgnat: is_ts,
            note: format!("x224_read_timeout: {}", err),
        },
    }
}

pub fn escape_json(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

impl RdpProbeReport {
    pub fn to_json(&self, cpu_threads: usize) -> String {
        format!(
            "{{\"engine\":\"xyrdp-probe-rust\",\"target\":\"{}\",\"reachable\":{},\"x224_confirmed\":{},\"selected_protocol\":{},\"rtt_ms\":{},\"tailscale_cgnat\":{},\"cpu_threads\":{},\"note\":\"{}\"}}",
            escape_json(&self.target),
            self.reachable,
            self.x224_confirmed,
            self.selected_protocol,
            self.rtt_ms,
            self.tailscale_cgnat,
            cpu_threads,
            escape_json(&self.note)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_tailscale_cgnat_bounds() {
        assert!(is_tailscale_cgnat(Ipv4Addr::new(100, 64, 0, 1)));
        assert!(is_tailscale_cgnat(Ipv4Addr::new(100, 101, 42, 88)));
        assert!(is_tailscale_cgnat(Ipv4Addr::new(100, 127, 255, 254)));
        assert!(!is_tailscale_cgnat(Ipv4Addr::new(100, 63, 255, 255)));
        assert!(!is_tailscale_cgnat(Ipv4Addr::new(100, 128, 0, 1)));
        assert!(!is_tailscale_cgnat(Ipv4Addr::new(192, 168, 1, 10)));
    }

    #[test]
    fn parses_valid_x224_confirm_pdu() {
        let valid_cc: [u8; 19] = [
            0x03, 0x00, 0x00, 0x13, 0x0e, 0xd0, 0x00, 0x01, 0x12, 0x34, 0x00, 0x02, 0x0f, 0x08,
            0x00, 0x02, 0x00, 0x00, 0x00,
        ];
        assert_eq!(parse_x224_confirm(&valid_cc), Some(2));
        assert_eq!(parse_x224_confirm(&[0x03, 0x00, 0x00]), None);
    }

    #[test]
    fn formats_clean_json() {
        let rep = RdpProbeReport {
            target: "100.90.12.34:3389".into(),
            reachable: true,
            x224_confirmed: true,
            selected_protocol: 2,
            rtt_ms: 4,
            tailscale_cgnat: true,
            note: "rdp_x224_ready".into(),
        };
        let js = rep.to_json(4);
        assert!(js.contains("\"x224_confirmed\":true"));
        assert!(js.contains("\"tailscale_cgnat\":true"));
    }
}
