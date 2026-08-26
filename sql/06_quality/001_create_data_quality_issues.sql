CREATE TABLE IF NOT EXISTS audit.data_quality_issues (
    issue_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    raw_record_id BIGINT NOT NULL,

    field_name TEXT,
    issue_code TEXT NOT NULL,

    severity TEXT NOT NULL,
    action TEXT NOT NULL,

    original_value TEXT,

    detected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_quality_severity
        CHECK (severity IN ('WARNING', 'ERROR')),

    CONSTRAINT chk_quality_action
        CHECK (action IN (
            'CLEAN',
            'NULLIFY',
            'FLAG',
            'FALLBACK',
            'REJECT'
        )),

    CONSTRAINT uq_quality_issue
        UNIQUE (
            source_schema,
            source_table,
            raw_record_id,
            issue_code
        )
);