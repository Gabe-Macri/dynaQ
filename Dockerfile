# ==============================================================================
# dynaQ Minimalist Containerized CLI & Documentation Environment
# Multi-stage Alpine build for ultra-lightweight footprint (< 20 MB)
# ==============================================================================

# Stage 1: Build Core C DSP Kernel CLI
FROM alpine:3.20 AS builder

RUN apk add --no-cache gcc musl-dev make

WORKDIR /src
COPY Sources/CDspKernel /src/Sources/CDspKernel
COPY docker/cli_main.c /src/docker/cli_main.c

RUN gcc -O3 -std=c11 -D_POSIX_C_SOURCE=199309L \
    docker/cli_main.c \
    Sources/CDspKernel/CDspKernel.c \
    -I Sources/CDspKernel/include \
    -lm \
    -o /src/dynaq-cli

# Stage 2: Minimalist Runtime Image
FROM alpine:3.20

RUN apk add --no-cache busybox-extras ca-certificates

WORKDIR /app

# Install compiled CLI tools
COPY --from=builder /src/dynaq-cli /usr/local/bin/dynaq-cli
RUN ln -s /usr/local/bin/dynaq-cli /usr/local/bin/dynaq

# Copy technical documentation
COPY docs /app/docs

# Entrypoint script
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose documentation server port
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
