# ollama/ollama has had no version tag newer than the ones checked here as
# of this hardening pass; pinned to the latest published release + its
# manifest digest rather than :latest.
FROM ollama/ollama:0.32.0@sha256:57f573b47f1f71ebb445789f279fe3e596a8beab182f7cf486db9205bad87c5a
RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin ollama && \
    mkdir -p /home/ollama/.ollama/models && \
    chown -R ollama:ollama /home/ollama
COPY --chown=ollama:ollama entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENV HOME=/home/ollama \
    OLLAMA_MODELS=/home/ollama/.ollama/models
USER ollama:ollama
ENTRYPOINT ["/entrypoint.sh"]
