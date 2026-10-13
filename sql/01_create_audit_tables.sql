-- Coastal Care Data Platform: audit tables
-- Safe to rerun (idempotent).

-- One row per attempt to load a source file into bronze.
CREATE TABLE IF NOT EXISTS audit.load_manifest (
    batch_id               UUID PRIMARY KEY,
    source_system          TEXT        NOT NULL,
    source_file            TEXT        NOT NULL,
    file_sha256            CHAR(64)    NOT NULL,
    file_size_bytes        BIGINT      NOT NULL,
    target_table           TEXT        NOT NULL,
    source_row_count       BIGINT,
    loaded_row_count       BIGINT,
    control_amount_columns TEXT,
    source_control_amount  NUMERIC(18, 2),
    loaded_control_amount  NUMERIC(18, 2),
    status                 TEXT        NOT NULL
        CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED', 'SKIPPED')),
    message                TEXT,
    started_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at            TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_load_manifest_file
    ON audit.load_manifest (source_file, file_sha256, status);
