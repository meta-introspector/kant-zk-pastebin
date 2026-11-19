// SVG animation — async: writes job file for svg2anim-worker systemd service.
use actix_web::{web, HttpResponse, Result};
use log::{error, info};
use std::{env, fs, path::Path};


/// POST /svg2anim/{id} -- submit SVG for animation (async, worker processes)
///
/// The `id` may be either:
///   - The full filename stem (e.g. `20260710_191143_download_svg`)
///   - A short UUID fragment (e.g. `3654b8d7_2246_4a39_ba36_bf19d80174ee`)
///
/// We mirror `get_file`'s two-pass lookup:
///   1. Exact stem match: `stem == id`
///   2. Suffix match:     `stem.ends_with(&format!("_{}", id))`
/// The resolved full stem is written into the job file so the worker
/// can find the SVG without re-doing the lookup.

// Experimental Linux x86_64 descriptor-based job publisher.
// Requires trusted UUCP_SPOOL and pre-provisioned directories.
#[cfg(target_arch = "x86_64")]
mod secure_jobs {
    use std::ffi::CString;
    use std::fs::{self, File};
    use std::io::{self, Write};
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::os::raw::{c_char, c_int, c_long};

const SYS_OPENAT2: c_long = 437;
const O_RDONLY: u64 = 0;
const O_WRONLY: u64 = 1;
const O_CREAT: u64 = 0o100;
const O_EXCL: u64 = 0o200;
const O_NOFOLLOW: u64 = 0o400000;
const O_DIRECTORY: u64 = 0o200000;
const O_CLOEXEC: u64 = 0o2000000;
const RESOLVE_NO_SYMLINKS: u64 = 0x04;
const RESOLVE_BENEATH: u64 = 0x08;

#[repr(C)]
struct OpenHow {
    flags: u64,
    mode: u64,
    resolve: u64,
}

unsafe extern "C" {
    fn syscall(number: c_long, ...) -> c_long;

    fn linkat(
        oldfd: c_int,
        old: *const c_char,
        newfd: c_int,
        new: *const c_char,
        flags: c_int,
    ) -> c_int;

    fn unlinkat(
        fd: c_int,
        name: *const c_char,
        flags: c_int,
    ) -> c_int;
}

fn c_name(value: &str) -> io::Result<CString> {
    CString::new(value).map_err(|_| {
        io::Error::new(io::ErrorKind::InvalidInput, "NUL")
    })
}

fn open_relative(
    directory: &File,
    relative: &str,
    flags: u64,
    mode: u64,
) -> io::Result<File> {
    let name = c_name(relative)?;

    let how = OpenHow {
        flags: flags | O_CLOEXEC | O_NOFOLLOW,
        mode,
        resolve: RESOLVE_NO_SYMLINKS | RESOLVE_BENEATH,
    };

    let fd = unsafe {
        syscall(
            SYS_OPENAT2,
            directory.as_raw_fd(),
            name.as_ptr(),
            &how as *const OpenHow,
            std::mem::size_of::<OpenHow>(),
        )
    };

    if fd < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(unsafe { File::from_raw_fd(fd as c_int) })
    }
}

pub(super) fn open_directories(spool: &File) -> io::Result<(File, File)> {
    let staging = open_relative(
        spool, "svg2anim-staging",
        O_RDONLY | O_DIRECTORY, 0,
    )?;

    let jobs = open_relative(
        spool, "svg2anim-jobs",
        O_RDONLY | O_DIRECTORY, 0,
    )?;

    Ok((staging, jobs))
}

pub(super) fn publish(
    staging: &File,
    jobs: &File,
    id: &str,
    body: &[u8],
    serial: u64,
) -> io::Result<()> {
    if id.is_empty()
        || id.len() > 200
        || !id.bytes().all(|b| {
            b.is_ascii_alphanumeric() || b == b'-' || b == b'_'
        })
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid job id",
        ));
    }

    let temporary = c_name(&format!(
        ".stage-{}-{serial}",
        std::process::id(),
    ))?;
    let final_name = c_name(id)?;

    let mut file = open_relative(
        staging,
        temporary.as_c_str().to_str().unwrap(),
        O_WRONLY | O_CREAT | O_EXCL,
        0o600,
    )?;

    let write_result = file
        .write_all(body)
        .and_then(|_| file.sync_all());

    drop(file);

    if let Err(error) = write_result {
        unsafe {
            unlinkat(staging.as_raw_fd(), temporary.as_ptr(), 0);
        }
        return Err(error);
    }

    let link_rc = unsafe {
        linkat(
            staging.as_raw_fd(),
            temporary.as_ptr(),
            jobs.as_raw_fd(),
            final_name.as_ptr(),
            0,
        )
    };

    let link_error = if link_rc != 0 {
        Some(io::Error::last_os_error())
    } else {
        None
    };

    let unlink_rc = unsafe {
        unlinkat(staging.as_raw_fd(), temporary.as_ptr(), 0)
    };

    let cleanup_error = if unlink_rc != 0 {
        Some(io::Error::last_os_error())
    } else {
        None
    };

    if let Some(error) = link_error {
        return Err(error);
    }

    jobs.sync_all()?;
    staging.sync_all()?;

    if let Some(error) = cleanup_error {
        return Err(error);
    }

    Ok(())
}


}

pub async fn svg2anim(path: web::Path<String>) -> Result<HttpResponse> {
    use std::io::Write;

    let id = path.into_inner();

    let valid_id = !id.is_empty()
        && id.len() <= 200
        && id.bytes().all(|b| {
            b.is_ascii_alphanumeric() || b == b'_' || b == b'-'
        });

    if !valid_id {
        return Ok(HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "invalid SVG id"})));
    }

    let uucp_dir = env::var("UUCP_SPOOL")
        .unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let jobs_dir = format!("{}/svg2anim-jobs", uucp_dir);

    let svg_dir = Path::new(&uucp_dir);
    let entries = fs::read_dir(svg_dir)
        .map_err(actix_web::error::ErrorInternalServerError)?;

    let mut exact = Vec::new();
    let mut suffix = Vec::new();

    for entry in entries {
        let entry = entry
            .map_err(actix_web::error::ErrorInternalServerError)?;

        // Reject symlinks at enumeration time.
        if !entry.file_type()
            .map_err(actix_web::error::ErrorInternalServerError)?
            .is_file()
        {
            continue;
        }

        let filename = entry.file_name();
        let Some(name) = filename.to_str() else {
            continue;
        };

        let Some(stem) = name.strip_suffix(".svg") else {
            continue;
        };

        let valid_stem = !stem.is_empty()
            && stem.len() <= 200
            && stem.bytes().all(|b| {
                b.is_ascii_alphanumeric() || b == b'_' || b == b'-'
            });

        if !valid_stem {
            continue;
        }

        if stem == id {
            exact.push(entry.path());
        } else if stem.ends_with(&format!("_{}", id)) {
            suffix.push(entry.path());
        }
    }

    let matches = if exact.is_empty() { &suffix } else { &exact };

    if matches.is_empty() {
        return Ok(HttpResponse::NotFound()
            .json(serde_json::json!({"error": "SVG not found"})));
    }

    if matches.len() != 1 {
        return Ok(HttpResponse::Conflict()
            .json(serde_json::json!({"error": "ambiguous SVG id"})));
    }

    let svg_path = &matches[0];
    let Some(resolved_id) = svg_path
        .file_stem()
        .and_then(|name| name.to_str())
    else {
        return Ok(HttpResponse::BadRequest().finish());
    };

    // Fail closed on unsupported architectures.
    #[cfg(not(target_arch = "x86_64"))]
    return Err(actix_web::error::ErrorInternalServerError(
        "secure job publication requires Linux x86_64",
    ));

    #[cfg(target_arch = "x86_64")]
    {
        let spool = fs::File::open(&uucp_dir)
            .map_err(actix_web::error::ErrorInternalServerError)?;

        if !spool.metadata()
            .map_err(actix_web::error::ErrorInternalServerError)?
            .is_dir()
        {
            return Err(actix_web::error::ErrorInternalServerError(
                "UUCP_SPOOL is not a directory",
            ));
        }

        // Directories must exist before starting the application.
        // openat2 rejects symlinks in both relative directory names.
        let (staging, jobs) = secure_jobs::open_directories(&spool)
            .map_err(actix_web::error::ErrorInternalServerError)?;

        static COUNTER: std::sync::atomic::AtomicU64 =
            std::sync::atomic::AtomicU64::new(0);

        let serial = COUNTER.fetch_add(
            1, std::sync::atomic::Ordering::Relaxed
        );

        let svg_path_str = svg_path.to_string_lossy().to_string();
        let job_path = Path::new(&jobs_dir).join(resolved_id);

        match secure_jobs::publish(
            &staging,
            &jobs,
            resolved_id,
            svg_path_str.as_bytes(),
            serial,
        ) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                return Ok(HttpResponse::Conflict().json(
                    serde_json::json!({"error": "job already exists"})
                ));
            }
            Err(error) => {
                return Err(
                    actix_web::error::ErrorInternalServerError(error)
                );
            }
        }

        info!("[svg2anim] Experimental job submitted: {}", resolved_id);

        return Ok(HttpResponse::Accepted().json(serde_json::json!({
            "status": "submitted",
            "id": resolved_id,
            "message": "Animation job submitted",
            "job_file": job_path,
        })));
    }
}
