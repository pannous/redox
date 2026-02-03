use redox_scheme::{scheme::register_sync_scheme, RequestKind, SignalBehavior, Socket};
use syscall::error::{ENODEV, ENOENT};

use scheme::ZeroScheme;

mod scheme;

enum Ty {
    Null,
    Zero,
}

fn main() {
    daemon::Daemon::new(daemon);
}

fn daemon(daemon: daemon::Daemon) -> ! {
    let ty = match &*std::env::args().next().unwrap() {
        "nulld" => Ty::Null,
        "zerod" => Ty::Zero,
        _ => panic!("needs to be called as either nulld or zerod"),
    };

    let name = match ty {
        Ty::Null => "null",
        Ty::Zero => "zero",
    };
    const MAX_RETRIES: usize = 200;
    let mut retries = 0;
    let socket = loop {
        match Socket::create() {
            Ok(socket) => break socket,
            Err(err) if err.errno == ENODEV || err.errno == ENOENT => {
                retries += 1;
                if retries >= MAX_RETRIES {
                    panic!("zerod: failed to create zero scheme: {}", err);
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(err) => panic!("zerod: failed to create zero scheme: {}", err),
        }
    };
    let mut zero_scheme = ZeroScheme(ty);

    register_sync_scheme(&socket, name, &mut zero_scheme)
        .expect("zerod: failed to register scheme to namespace");

    daemon.ready();

    libredox::call::setrens(0, 0).expect("zerod: failed to enter null namespace");

    loop {
        let Some(request) = socket
            .next_request(SignalBehavior::Restart)
            .expect("zerod: failed to read events from zero scheme")
        else {
            std::process::exit(0);
        };
        match request.kind() {
            RequestKind::Call(request) => {
                let response = request.handle_sync(&mut zero_scheme);

                socket
                    .write_response(response, SignalBehavior::Restart)
                    .expect("zerod: failed to write responses to zero scheme");
            }
            _ => (),
        }
    }
}
