ALTER TABLE audit.data_quality_issues
ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

ALTER TABLE audit.data_quality_issues
ADD COLUMN IF NOT EXISTS resolution_note TEXT;