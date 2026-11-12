FROM rust:1.85-slim as builder

WORKDIR /build

ENV CARGO_REGISTRIES_NORA_INDEX=sparse+https://solana.solfunmeme.com/nora/cargo/index/
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY build.rs ./

RUN cargo build --locked --release

FROM debian:bookworm-slim

# Install IPFS (kubo)
RUN apt-get update && apt-get install -y \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://dist.ipfs.tech/kubo/v0.27.0/kubo_v0.27.0_linux-amd64.tar.gz \
    && tar -xzf kubo_v0.27.0_linux-amd64.tar.gz \
    && mv kubo/ipfs /usr/local/bin/ \
    && rm -rf kubo kubo_v0.27.0_linux-amd64.tar.gz

# Copy pastebin binary
COPY --from=builder /build/target/release/kant-pastebin /usr/local/bin/

# Setup directories
RUN mkdir -p /data/pastebin /data/ipfs
ENV IPFS_PATH=/data/ipfs
ENV UUCP_SPOOL=/data/pastebin
ENV BIND_ADDR=0.0.0.0:7860
ENV BASE_PATH=
ENV RUST_LOG=info

# Initialize IPFS
RUN ipfs init --profile=lowpower

# Startup script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 7860

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
